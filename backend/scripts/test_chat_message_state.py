"""Chat message idempotency + timestamp checks (see CHAT_MESSAGE_STATE_FIX.md).

Covers both bugs from the 2026-10-30 report, for every chat-enabled role
(doctor REST, farmer REST, and the Socket.IO send path):

  * One send = one row; replaying the same ``client_message_id`` returns the
    original (200, same id) without a second row, notification or broadcast;
    different ids create separate rows; concurrent duplicate submits create
    exactly one row; reusing an id in another conversation is refused (409);
    sends without an id (older clients) still work.
  * ``sent_at`` is the server time, returned as ISO 8601 with a UTC offset —
    identical in the send response, the sender's list and the recipient's
    list, stable across repeated fetches, and correct for legacy rows that
    were stored before this fix. Lists are ordered by ``sent_at``.
  * Sender and recipient lists each contain the message exactly once, and the
    recipient gets exactly one notification.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_chat_message_state.py

Uses Django's test Client against the *live* configured database. Creates
throw-away accounts prefixed ``chatstate+`` only (never the seeded demo
users) and cleans its own rows on entry and on exit. Idempotent.
"""
import os
import sys
import threading
import uuid
from datetime import date, datetime, timedelta, timezone as dt_timezone

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from asgiref.sync import async_to_sync  # noqa: E402
from django.db import connection  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from doctor.models import Conversation, Message  # noqa: E402
from messaging.realtime import persist_message  # noqa: E402
from notifications.models import Notification  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'chatstate+'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def make_user(handle, role_name):
    import hashlib
    email = f'{PREFIX}{handle}@featherflow.dev'
    phone = '+8801' + hashlib.md5(email.encode()).hexdigest()[:9]
    user, _ = User.objects.get_or_create(email=email, defaults=dict(
        full_name=f'CS {handle.title()}', phone=phone, date_of_birth=date(1990, 1, 1),
        present_address='Dhaka', consent_terms=True, account_status='active',
    ))
    user.account_status = 'active'
    user.save()
    role, _ = Role.objects.get_or_create(name=role_name, defaults={'panel_type': role_name})
    user.roles.clear()
    user.roles.add(role)
    return user


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def cleanup(users):
    ids = [u.id for u in users]
    convs = Conversation.objects.filter(participant_one_id__in=ids) | Conversation.objects.filter(participant_two_id__in=ids)
    conv_ids = list(convs.values_list('id', flat=True))
    Message.objects.filter(conversation_id__in=conv_ids).delete()
    Conversation.objects.filter(id__in=conv_ids).delete()
    Notification.objects.filter(user_id__in=ids).delete()


def parse(iso):
    return datetime.fromisoformat(iso) if iso else None


def main():
    doctor = make_user('vet', 'doctor')
    farmer = make_user('farmer', 'farmer')
    farmer2 = make_user('farmer2', 'farmer')
    users = [doctor, farmer, farmer2]
    cleanup(users)
    conv = Conversation.objects.create(participant_one=farmer, participant_two=doctor)
    other_conv = Conversation.objects.create(participant_one=farmer2, participant_two=doctor)
    dc, fc = client_for(doctor), client_for(farmer)

    def doctor_send(content, client_id=None, conversation=conv):
        body = {'content': content}
        if client_id:
            body['client_message_id'] = client_id
        return dc.post(f'/api/doctor/conversations/{conversation.id}/', body, content_type='application/json')

    def farmer_send(content, client_id=None):
        body = {'content': content}
        if client_id:
            body['client_message_id'] = client_id
        return fc.post(f'/api/consultations/chats/{conv.id}/', body, content_type='application/json')

    def doctor_list():
        rows = dc.get('/api/doctor/conversations/').json()['conversations']
        return next(r for r in rows if r['id'] == str(conv.id))

    def farmer_list():
        rows = fc.get('/api/consultations/chats/').json()['conversations']
        return next(r for r in rows if r['id'] == str(conv.id))

    def notes(user):
        return Notification.objects.filter(user=user, reference_type='conversation').count()

    # ── one send, one row ────────────────────────────────────────────────────
    print('\n== doctor send: one tap -> one row ==')
    cid = str(uuid.uuid4())
    before = datetime.now(dt_timezone.utc)
    r = doctor_send('hello', cid)
    after = datetime.now(dt_timezone.utc)
    check('send 201', r.status_code == 201, r.content[:200])
    sent = r.json()
    check('response echoes client_message_id', sent.get('client_message_id') == cid, sent)
    check('exactly one DB row for the send', Message.objects.filter(conversation=conv).count() == 1)
    sent_at = parse(sent.get('sent_at'))
    check('sent_at is ISO 8601 with a timezone', sent_at is not None and sent_at.utcoffset() is not None, sent.get('sent_at'))
    check('sent_at is the server time of the send',
          sent_at is not None and before - timedelta(seconds=1) <= sent_at <= after + timedelta(seconds=1),
          (before, sent.get('sent_at'), after))
    check('recipient got exactly one notification', notes(farmer) == 1, notes(farmer))

    print('\n== retry with the same client_message_id ==')
    r2 = doctor_send('hello', cid)
    check('replay returns 200 (not 201)', r2.status_code == 200, r2.content[:200])
    check('replay returns the ORIGINAL message', r2.json().get('id') == sent['id'], r2.json())
    check('replay keeps the original timestamp', r2.json().get('sent_at') == sent['sent_at'], r2.json())
    check('still exactly one DB row', Message.objects.filter(conversation=conv).count() == 1)
    check('replay does not notify again', notes(farmer) == 1, notes(farmer))

    print('\n== different client ids are different messages ==')
    r3 = doctor_send('hello', str(uuid.uuid4()))
    check('same text, new client id -> 201 new row',
          r3.status_code == 201 and r3.json()['id'] != sent['id'], r3.content[:200])
    r4 = doctor_send('no id (older client)')
    check('send without client_message_id still works', r4.status_code == 201, r4.content[:200])
    check('three rows now', Message.objects.filter(conversation=conv).count() == 3)

    print('\n== client id reused in another conversation ==')
    r5 = doctor_send('elsewhere', cid, conversation=other_conv)
    check('refused with 409 + detail', r5.status_code == 409 and 'detail' in r5.json(), r5.content[:200])
    r6 = doctor_send('bad id', 'not-a-uuid')
    check('malformed client_message_id -> 400', r6.status_code == 400, r6.content[:200])

    # ── concurrent duplicate submits ─────────────────────────────────────────
    print('\n== concurrent duplicate submits ==')
    race_id = str(uuid.uuid4())
    results = []
    barrier = threading.Barrier(5)

    def racer():
        try:
            c = client_for(farmer)
            barrier.wait()
            resp = c.post(f'/api/consultations/chats/{conv.id}/',
                          {'content': 'race', 'client_message_id': race_id},
                          content_type='application/json')
            results.append((resp.status_code, resp.json().get('id')))
        finally:
            connection.close()

    threads = [threading.Thread(target=racer) for _ in range(5)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()
    rows = Message.objects.filter(conversation=conv, client_message_id=race_id).count()
    check('5 simultaneous submits -> exactly one row', rows == 1, (rows, results))
    check('all 5 responses point at the same message',
          len({mid for _, mid in results}) == 1 and len(results) == 5, results)
    check('exactly one 201, the rest 200',
          sorted(code for code, _ in results) == [200, 200, 200, 200, 201], results)

    # ── farmer send + both lists ─────────────────────────────────────────────
    print('\n== farmer send, both lists, timestamps ==')
    fcid = str(uuid.uuid4())
    r = farmer_send('hi doctor', fcid)
    check('farmer send 201 with from_me', r.status_code == 201 and r.json().get('from_me') is True, r.content[:200])
    fsent = r.json()
    check('farmer replay -> same message', farmer_send('hi doctor', fcid).json().get('id') == fsent['id'])

    d_rows, f_rows = doctor_list()['messages'], farmer_list()['messages']
    for label, rows in (('doctor', d_rows), ('farmer', f_rows)):
        check(f'{label} list has the doctor message exactly once',
              sum(1 for m in rows if m['id'] == sent['id']) == 1, [m['id'] for m in rows])
        check(f'{label} list has the farmer message exactly once',
              sum(1 for m in rows if m['id'] == fsent['id']) == 1)
        check(f'{label} list: every sent_at carries a timezone',
              all(parse(m['sent_at']).utcoffset() is not None for m in rows), [m['sent_at'] for m in rows])
        check(f'{label} list: ordered by sent_at',
              [parse(m['sent_at']) for m in rows] == sorted(parse(m['sent_at']) for m in rows))
        check(f'{label} list exposes client_message_id',
              next(m for m in rows if m['id'] == sent['id'])['client_message_id'] == cid)
    d_msg = next(m for m in d_rows if m['id'] == sent['id'])
    f_msg = next(m for m in f_rows if m['id'] == sent['id'])
    check('sender and recipient see the identical server timestamp',
          d_msg['sent_at'] == f_msg['sent_at'] == sent['sent_at'], (d_msg['sent_at'], f_msg['sent_at'], sent['sent_at']))
    check('authorship is viewer-relative',
          d_msg['from_doctor'] is True and d_msg['from_me'] is True and f_msg['from_me'] is False)
    check('repeated fetch returns the same timestamp',
          next(m for m in doctor_list()['messages'] if m['id'] == sent['id'])['sent_at'] == sent['sent_at'])
    check('last_message_at carries a timezone', parse(doctor_list()['last_message_at']).utcoffset() is not None)

    # A row stored before this fix (no client id, naive UTC wall clock).
    legacy = Message.objects.create(conversation=conv, sender=farmer, content='legacy',
                                    sent_at=datetime(2026, 9, 29, 16, 37, 55, tzinfo=dt_timezone.utc))
    row = next(m for m in farmer_list()['messages'] if m['id'] == str(legacy.id))
    check('legacy row read back naive is labelled UTC (not left offset-less)',
          row['sent_at'] == '2026-09-29T16:37:55+00:00', row['sent_at'])
    check('legacy row sorts first by time', farmer_list()['messages'][0]['id'] == str(legacy.id))

    # Marking read must not touch timestamps.
    before_ts = {m['id']: m['sent_at'] for m in farmer_list()['messages']}
    fc.patch(f'/api/consultations/chats/{conv.id}/', {}, content_type='application/json')
    after_ts = {m['id']: m['sent_at'] for m in farmer_list()['messages']}
    check('mark-read leaves every timestamp unchanged', before_ts == after_ts)

    # ── Socket.IO send path ──────────────────────────────────────────────────
    print('\n== Socket.IO send path ==')
    scid = str(uuid.uuid4())
    payload, created = async_to_sync(persist_message)(str(doctor.id), str(conv.id),
                                                      {'content': 'via socket', 'client_message_id': scid})
    check('socket send creates the message', created and payload['client_message_id'] == scid, payload)
    check('socket payload sent_at has a timezone', parse(payload['sent_at']).utcoffset() is not None, payload)
    again, created2 = async_to_sync(persist_message)(str(doctor.id), str(conv.id),
                                                     {'content': 'via socket', 'client_message_id': scid})
    check('socket replay returns the original, not broadcast again',
          created2 is False and again['id'] == payload['id'], again)
    check('socket path: still one row for that id',
          Message.objects.filter(client_message_id=scid).count() == 1)
    check('socket path refuses a non-participant',
          async_to_sync(persist_message)(str(farmer2.id), str(conv.id), {'content': 'x'}) is None)

    print(f'\n{PASS} passed, {FAIL} failed')
    cleanup(users)
    return FAIL


if __name__ == '__main__':
    sys.exit(1 if main() else 0)
