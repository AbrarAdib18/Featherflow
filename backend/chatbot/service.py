"""Request validation, PII scrubbing and reply parsing for the chat endpoint."""
import json
import re

from .knowledge import REFUSAL_MESSAGE, SYSTEM_PROMPT
from .providers import ProviderError

MAX_MESSAGE_CHARS = 1000
MAX_HISTORY_TURNS = 6
MAX_REPLY_CHARS = 4000

_EMAIL = re.compile(r'[\w.+-]+@[\w-]+(?:\.[\w-]+)+')
_LONG_DIGITS = re.compile(r'(?<!\w)\+?\d[\d\s().-]{7,}\d(?!\w)')
_SECRET_LIKE = re.compile(r'\b(?:AIza|AQ\.|sk-|eyJ)[\w.\-]{12,}')


def scrub(text):
    """Drop contact details, long numbers and key-like tokens before text
    leaves the server. Poultry questions never need them."""
    text = _SECRET_LIKE.sub('[removed]', text)
    text = _EMAIL.sub('[email removed]', text)
    return _LONG_DIGITS.sub('[number removed]', text)


def validate_payload(data):
    """Returns (message, history, errors). ``errors`` maps field -> text."""
    if not isinstance(data, dict):
        return None, [], {'non_field_errors': 'Request body must be a JSON object.'}
    errors = {}
    message = data.get('message')
    if not isinstance(message, str) or not message.strip():
        errors['message'] = 'Message is required.'
    elif len(message) > MAX_MESSAGE_CHARS:
        errors['message'] = f'Message is too long (max {MAX_MESSAGE_CHARS} characters).'
    raw_history = data.get('history') or []
    history = []
    if not isinstance(raw_history, list):
        errors['history'] = 'History must be a list.'
    else:
        for item in raw_history[-MAX_HISTORY_TURNS:]:
            if (not isinstance(item, dict) or item.get('role') not in ('user', 'assistant')
                    or not isinstance(item.get('text'), str)):
                errors['history'] = 'Each history item needs role (user/assistant) and text.'
                break
            history.append({'role': item['role'], 'text': item['text'][:MAX_MESSAGE_CHARS]})
    if errors:
        return None, [], errors
    return message.strip(), history, {}


def build_turns(message, history):
    """Alternating user/model turns starting and ending with a user turn."""
    turns = []
    for h in history:
        role = 'model' if h['role'] == 'assistant' else 'user'
        text = scrub(h['text'])
        if turns and turns[-1]['role'] == role:
            turns[-1]['text'] += '\n' + text
        else:
            turns.append({'role': role, 'text': text})
    while turns and turns[0]['role'] == 'model':
        turns.pop(0)
    if turns and turns[-1]['role'] == 'user':
        turns[-1]['text'] += '\n' + scrub(message)
    else:
        turns.append({'role': 'user', 'text': scrub(message)})
    return turns


def parse_reply(raw):
    """Parse the model's JSON contract. Returns (in_scope, reply)."""
    bad = ProviderError('invalid_response', 'The AI service returned an unreadable response.')
    if not isinstance(raw, str):
        raise bad
    text = raw.strip()
    if text.startswith('```'):
        text = re.sub(r'^```(?:json)?\s*|\s*```$', '', text)
    try:
        obj = json.loads(text)
    except ValueError:
        raise bad from None
    if (not isinstance(obj, dict) or not isinstance(obj.get('in_scope'), bool)
            or not isinstance(obj.get('reply'), str)):
        raise bad
    if not obj['in_scope'] or not obj['reply'].strip():
        return False, REFUSAL_MESSAGE
    return True, obj['reply'].strip()[:MAX_REPLY_CHARS]


def ask(provider, message, history):
    raw = provider.generate(SYSTEM_PROMPT, build_turns(message, history))
    return parse_reply(raw)
