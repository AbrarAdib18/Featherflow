"""LLM provider layer. The only module that talks to Gemini.

The API key is read from the GEMINI_API_KEY environment variable at call time,
sent in a request header (never in the URL), and is never logged or returned.
Tests replace ``get_provider`` with a fake.
"""
import json
import logging
import os
import socket
import time
import urllib.error
import urllib.request

logger = logging.getLogger('chatbot')

DEFAULT_MODEL = 'gemini-3.5-flash'
DEFAULT_FALLBACK_MODEL = 'gemini-3.1-flash-lite'
# Gemini answers 500/503 during demand spikes; a short retry usually succeeds.
RETRY_STATUSES = (500, 502, 503, 504)
MAX_ATTEMPTS = 3
RETRY_DELAY_SECONDS = 1.5
ENDPOINT = 'https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent'


class ProviderError(Exception):
    """A provider failure with a stable, key-free ``code`` and user message."""

    def __init__(self, code, message):
        super().__init__(message)
        self.code = code
        self.message = message


class NotConfigured(ProviderError):
    def __init__(self):
        super().__init__(
            'not_configured',
            'The AI assistant is not configured on this server. '
            'An administrator must set GEMINI_API_KEY.')


def api_key():
    return os.environ.get('GEMINI_API_KEY', '').strip()


class GeminiProvider:
    def __init__(self):
        key = api_key()
        if not key:
            raise NotConfigured()
        self._key = key
        self.model = os.environ.get('GEMINI_MODEL', '').strip() or DEFAULT_MODEL
        self.fallback_model = (os.environ.get('GEMINI_FALLBACK_MODEL', '').strip()
                               or DEFAULT_FALLBACK_MODEL)
        self.timeout = float(os.environ.get('CHATBOT_TIMEOUT_SECONDS', '20'))

    def generate(self, system_prompt, turns):
        """Try the primary model; if it is overloaded, try the fallback once."""
        try:
            return self._generate_one(self.model, system_prompt, turns)
        except ProviderError as exc:
            if exc.code != 'provider_unavailable' or self.fallback_model == self.model:
                raise
            logger.warning('chatbot falling back to %s', self.fallback_model)
            return self._generate_one(self.fallback_model, system_prompt, turns)

    def _generate_one(self, model, system_prompt, turns):
        """``turns``: list of {"role": "user"|"model", "text": str}.
        Returns the raw model text (expected to be a JSON string)."""
        body = {
            'systemInstruction': {'parts': [{'text': system_prompt}]},
            'contents': [{'role': t['role'], 'parts': [{'text': t['text']}]} for t in turns],
            'generationConfig': {
                'temperature': 0.3,
                'maxOutputTokens': 1500,
                'responseMimeType': 'application/json',
            },
        }
        req = urllib.request.Request(
            ENDPOINT.format(model=model),
            data=json.dumps(body).encode('utf-8'),
            headers={'Content-Type': 'application/json', 'x-goog-api-key': self._key},
            method='POST',
        )
        payload = None
        for attempt in range(1, MAX_ATTEMPTS + 1):
            try:
                with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                    payload = json.loads(resp.read().decode('utf-8'))
                break
            except urllib.error.HTTPError as exc:
                # Never include the response body or URL in anything we raise or log.
                logger.warning('chatbot provider http status=%s model=%s attempt=%s',
                               exc.code, model, attempt)
                if exc.code in RETRY_STATUSES and attempt < MAX_ATTEMPTS:
                    time.sleep(RETRY_DELAY_SECONDS * attempt)
                    continue
                if exc.code == 429:
                    raise ProviderError('provider_rate_limited',
                                        'The AI service is busy. Please try again in a minute.') from None
                if exc.code in (400, 401, 403, 404):
                    raise ProviderError('provider_rejected',
                                        'The AI service rejected the request. '
                                        'Please contact an administrator.') from None
                raise ProviderError('provider_unavailable',
                                    'The AI service is temporarily busy. Please retry in a moment.') from None
            except (socket.timeout, TimeoutError):
                raise ProviderError('timeout',
                                    'The AI service took too long to respond. Please retry.') from None
            except urllib.error.URLError as exc:
                if isinstance(getattr(exc, 'reason', None), (socket.timeout, TimeoutError)):
                    raise ProviderError('timeout',
                                        'The AI service took too long to respond. Please retry.') from None
                logger.warning('chatbot provider network error=%s', type(exc.reason).__name__)
                raise ProviderError('provider_unavailable',
                                    'The AI service is temporarily unavailable. Please retry.') from None
            except (ValueError, OSError):
                raise ProviderError('invalid_response',
                                    'The AI service returned an unreadable response.') from None
        try:
            return payload['candidates'][0]['content']['parts'][0]['text']
        except (KeyError, IndexError, TypeError):
            raise ProviderError('invalid_response',
                                'The AI service returned an empty response.') from None


def get_provider():
    return GeminiProvider()
