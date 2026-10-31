"""Chatbot endpoint tests. The real Gemini API is never called: every test
swaps ``providers.get_provider`` for a fake, or hits the missing-key path."""
import json
import os
from unittest import mock

from django.core.cache import cache
from rest_framework.test import APITestCase

from users.models import Role, User

from . import providers
from .knowledge import REFUSAL_MESSAGE, SYSTEM_PROMPT

URL = '/api/chatbot/chat/'
FAKE_KEY = 'AQ.FAKE-TEST-KEY-0123456789abcdef'


class FakeProvider:
    """Stands in for GeminiProvider; replies per a simple topic rule."""

    def __init__(self, raw=None, error=None):
        self.raw = raw
        self.error = error
        self.calls = []

    def generate(self, system_prompt, turns):
        self.calls.append((system_prompt, turns))
        if self.error:
            raise self.error
        if self.raw is not None:
            return self.raw
        last = turns[-1]['text'].lower()
        if any(w in last for w in ('chicken', 'poultry', 'broiler', 'feed', 'featherflow')):
            return json.dumps({'in_scope': True,
                               'reply': 'Keep brooder temperature at 32-35C in week one.'})
        return json.dumps({'in_scope': False, 'reply': 'Sorry, off topic.'})


class ChatbotEndpointTests(APITestCase):
    def setUp(self):
        cache.clear()
        self.user = User.objects.create_user(
            email='chat-farmer@test.local', password='test', full_name='Chat Farmer',
            account_status='active', phone='01700000099', date_of_birth='1990-01-01',
            present_address='Test', consent_terms=True)
        role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
        self.user.roles.add(role)
        self.client.force_authenticate(self.user)
        env = mock.patch.dict(os.environ, {'GEMINI_API_KEY': FAKE_KEY})
        env.start()
        self.addCleanup(env.stop)

    def _use(self, provider):
        patcher = mock.patch('chatbot.providers.get_provider', return_value=provider)
        patcher.start()
        self.addCleanup(patcher.stop)
        return provider

    def test_authentication_required(self):
        self.client.force_authenticate(None)
        r = self.client.post(URL, {'message': 'hello chicken'}, format='json')
        self.assertIn(r.status_code, (401, 403))

    def test_valid_poultry_question_returns_reply(self):
        fake = self._use(FakeProvider())
        r = self.client.post(URL, {'message': 'How warm should broiler chicks be?'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertTrue(r.data['in_scope'])
        self.assertIsNone(r.data['error'])
        self.assertIn('brooder', r.data['reply'])
        self.assertEqual(fake.calls[0][0], SYSTEM_PROMPT)

    def test_off_topic_is_refused_with_fixed_message(self):
        self._use(FakeProvider())
        r = self.client.post(URL, {'message': 'Who won the football match?'}, format='json')
        self.assertEqual(r.status_code, 200)
        self.assertFalse(r.data['in_scope'])
        self.assertEqual(r.data['reply'], REFUSAL_MESSAGE)

    def test_model_cannot_smuggle_content_when_out_of_scope(self):
        self._use(FakeProvider(raw=json.dumps({'in_scope': False, 'reply': 'Buy shares in X!'})))
        r = self.client.post(URL, {'message': 'chicken stocks?'}, format='json')
        self.assertEqual(r.data['reply'], REFUSAL_MESSAGE)

    def test_missing_api_key_is_controlled_error(self):
        with mock.patch.dict(os.environ, {'GEMINI_API_KEY': ''}):
            r = self.client.post(URL, {'message': 'chicken feed?'}, format='json')
        self.assertEqual(r.status_code, 503)
        self.assertEqual(r.data['error']['code'], 'not_configured')
        self.assertIn('GEMINI_API_KEY', r.data['error']['message'])
        self.assertEqual(r.data['reply'], '')

    def test_invalid_bodies_rejected(self):
        self._use(FakeProvider())
        bad = [
            {},
            {'message': ''},
            {'message': '   '},
            {'message': 123},
            {'message': 'x' * 1001},
            {'message': 'chicken', 'history': 'nope'},
            {'message': 'chicken', 'history': [{'role': 'system', 'text': 'x'}]},
            {'message': 'chicken', 'history': [{'role': 'user'}]},
        ]
        for i, body in enumerate(bad):
            if i % 6 == 5:
                cache.clear()
            r = self.client.post(URL, body, format='json')
            self.assertEqual(r.status_code, 400, body)
            self.assertEqual(r.data['error']['code'], 'invalid_request')
        cache.clear()  # invalid requests still count toward the burst throttle
        r = self.client.post(URL, ['not', 'an', 'object'], format='json')
        self.assertEqual(r.status_code, 400)

    def test_history_is_trimmed_and_pii_scrubbed(self):
        fake = self._use(FakeProvider())
        history = [{'role': 'user' if i % 2 == 0 else 'assistant', 'text': f'turn {i} chicken'}
                   for i in range(20)]
        r = self.client.post(URL, {
            'message': 'My email is a.b@example.com phone +880 1711-223344 chicken?',
            'history': history}, format='json')
        self.assertEqual(r.status_code, 200)
        turns = fake.calls[0][1]
        self.assertLessEqual(len(turns), 7)
        self.assertEqual(turns[0]['role'], 'user')
        self.assertEqual(turns[-1]['role'], 'user')
        sent = json.dumps(turns)
        self.assertNotIn('a.b@example.com', sent)
        self.assertNotIn('1711-223344', sent)

    def test_provider_failures_are_graceful(self):
        cases = {
            'timeout': 504, 'provider_unavailable': 503, 'provider_rate_limited': 503,
            'provider_rejected': 502, 'invalid_response': 502,
        }
        for code, status in cases.items():
            cache.clear()
            self._use(FakeProvider(error=providers.ProviderError(code, 'm')))
            r = self.client.post(URL, {'message': 'chicken?'}, format='json')
            self.assertEqual(r.status_code, status, code)
            self.assertEqual(r.data['error']['code'], code)

    def test_malformed_model_output_is_invalid_response(self):
        for raw in ('not json', '[]', '{"reply": "x"}', '{"in_scope": "yes", "reply": "x"}', None):
            cache.clear()
            self._use(FakeProvider(raw=raw if raw is not None else 5))
            r = self.client.post(URL, {'message': 'chicken?'}, format='json')
            self.assertEqual(r.status_code, 502, raw)
            self.assertEqual(r.data['error']['code'], 'invalid_response')

    def test_unexpected_exception_is_masked(self):
        self._use(FakeProvider(error=RuntimeError(f'boom {FAKE_KEY}')))
        r = self.client.post(URL, {'message': 'chicken?'}, format='json')
        self.assertEqual(r.status_code, 502)
        self.assertNotIn(FAKE_KEY, json.dumps(r.data))

    def test_rate_limit(self):
        self._use(FakeProvider())
        statuses = [self.client.post(URL, {'message': 'chicken feed?'}, format='json').status_code
                    for _ in range(10)]
        self.assertEqual(statuses[:8], [200] * 8)
        self.assertEqual(statuses[8], 429)

    def test_key_never_in_responses_or_logs(self):
        self._use(FakeProvider())
        with self.assertLogs('chatbot.audit', level='INFO') as logs:
            responses = [
                self.client.post(URL, {'message': 'chicken feed?'}, format='json'),
                self.client.post(URL, {'message': ''}, format='json'),
                self.client.post(URL, {'message': f'my key is {FAKE_KEY} chicken'}, format='json'),
            ]
            with mock.patch.dict(os.environ, {'GEMINI_API_KEY': ''}):
                responses.append(self.client.post(URL, {'message': 'chicken'}, format='json'))
        blob = ' '.join(json.dumps(r.data) for r in responses) + ' '.join(logs.output)
        self.assertNotIn(FAKE_KEY, blob)
        self.assertNotIn('chicken feed?', ' '.join(logs.output))  # no message content logged
        self.assertIn('user=', ' '.join(logs.output))

    def test_key_in_user_message_is_not_forwarded(self):
        fake = self._use(FakeProvider())
        self.client.post(URL, {'message': f'chicken {FAKE_KEY}'}, format='json')
        self.assertNotIn(FAKE_KEY, json.dumps(fake.calls[0][1]))

    def test_gemini_provider_requires_key_and_hides_it_on_http_errors(self):
        with mock.patch.dict(os.environ, {'GEMINI_API_KEY': ''}):
            with self.assertRaises(providers.NotConfigured):
                providers.GeminiProvider()
        import urllib.error
        err = urllib.error.HTTPError('https://x/?key=' + FAKE_KEY, 403, 'no', {}, None)
        with mock.patch('urllib.request.urlopen', side_effect=err):
            with self.assertRaises(providers.ProviderError) as ctx:
                providers.GeminiProvider().generate('sys', [{'role': 'user', 'text': 'hi'}])
        self.assertNotIn(FAKE_KEY, ctx.exception.message)
        self.assertEqual(ctx.exception.code, 'provider_rejected')


class ProviderRetryTests(APITestCase):
    def setUp(self):
        env = mock.patch.dict(os.environ, {'GEMINI_API_KEY': FAKE_KEY})
        env.start()
        self.addCleanup(env.stop)

    def _http_error(self, code):
        import urllib.error
        return urllib.error.HTTPError('https://x/', code, 'e', {}, None)

    def test_transient_503_is_retried_then_succeeds(self):
        good = mock.MagicMock()
        good.__enter__.return_value.read.return_value = json.dumps(
            {'candidates': [{'content': {'parts': [{'text': '{"in_scope": true, "reply": "ok"}'}]}}]}
        ).encode()
        with mock.patch('time.sleep'), mock.patch(
                'urllib.request.urlopen',
                side_effect=[self._http_error(503), self._http_error(503), good]) as op:
            out = providers.GeminiProvider().generate('sys', [{'role': 'user', 'text': 'hi'}])
        self.assertIn('ok', out)
        self.assertEqual(op.call_count, 3)

    def test_overloaded_primary_falls_back_to_second_model(self):
        good = mock.MagicMock()
        good.__enter__.return_value.read.return_value = json.dumps(
            {'candidates': [{'content': {'parts': [{'text': '{"in_scope": true, "reply": "fb"}'}]}}]}
        ).encode()
        errs = [self._http_error(503)] * 3
        with mock.patch('time.sleep'), mock.patch('urllib.request.urlopen', side_effect=errs + [good]) as op:
            out = providers.GeminiProvider().generate('sys', [{'role': 'user', 'text': 'hi'}])
        self.assertIn('fb', out)
        self.assertIn(providers.DEFAULT_FALLBACK_MODEL, op.call_args[0][0].full_url)

    def test_persistent_503_gives_busy_error_without_key(self):
        with mock.patch('time.sleep'), mock.patch(
                'urllib.request.urlopen', side_effect=lambda *a, **k: (_ for _ in ()).throw(self._http_error(503))):
            with self.assertRaises(providers.ProviderError) as ctx:
                providers.GeminiProvider().generate('sys', [{'role': 'user', 'text': 'hi'}])
        self.assertEqual(ctx.exception.code, 'provider_unavailable')
        self.assertNotIn(FAKE_KEY, ctx.exception.message)

    def test_404_model_gone_is_not_retried(self):
        with mock.patch('time.sleep'), mock.patch(
                'urllib.request.urlopen', side_effect=[self._http_error(404)]) as op:
            with self.assertRaises(providers.ProviderError) as ctx:
                providers.GeminiProvider().generate('sys', [{'role': 'user', 'text': 'hi'}])
        self.assertEqual(ctx.exception.code, 'provider_rejected')
        self.assertEqual(op.call_count, 1)
