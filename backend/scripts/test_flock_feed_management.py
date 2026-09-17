"""Priority 4 — flock/feed management regression check.

Run:  backend/venv/Scripts/python.exe backend/scripts/test_flock_feed_management.py

Live DB, `flocktest+` prefixed throw-away accounts. Idempotent. Needs
`manage.py seed_feeding_guidelines` to have been run at least once.

Covers: flock CRUD, age_days calculation, feed-stage lookup, flock-event
quantity effects (mortality/sale decrement current_quantity, validation),
feeding-notification generation + same-day idempotency, and permission
isolation between farmers.
"""
import os
import sys
from datetime import date, timedelta

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.core.management import call_command  # noqa: E402
from django.test import Client  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from farms.models import Farm, Flock, FlockEvent  # noqa: E402
from feed.models import FeedingGuideline  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'flocktest+'
JSON = 'application/json'


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


def cleanup():
    users = User.objects.filter(email__startswith=PREFIX)
    farms = Farm.objects.filter(farmer__user__in=users)
    FlockEvent.objects.filter(flock__farm__in=farms).delete()
    Flock.objects.filter(farm__in=farms).delete()
    Notification.objects.filter(user__in=users).delete()
    farms.delete()
    FarmerProfile.objects.filter(user__in=users).delete()
    users.delete()


_n = [0]


def mk_farmer():
    _n[0] += 1
    n = _n[0]
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u = User.objects.create_user(
        email=f'{PREFIX}{n}@example.com', password='Test1234!',
        phone=f'0194{n:07d}', full_name=f'Farmer {n}',
        date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    return u


def client_for(user):
    c = Client()
    token = str(RefreshToken.for_user(user).access_token)
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {token}'
    return c


def run():
    print('\n== Priority 4: Flock/feed management regression ==\n')
    cleanup()
    if not FeedingGuideline.objects.exists():
        call_command('seed_feeding_guidelines')

    farmer = mk_farmer()
    c = client_for(farmer)
    fp, _ = FarmerProfile.objects.get_or_create(
        user=farmer, defaults={'farm_name': 'F', 'owner_name': 'F', 'farm_location': 'L', 'farm_address': 'A'})
    farm = Farm.objects.create(farmer=fp, farm_name='F', farm_type='mixed', location='L', address='A')

    # 1. Flock create + age calculation.
    start = date.today() - timedelta(days=5)
    r = c.post('/api/farmers/flocks/', {
        'batch_name': 'Batch-Age-Test', 'bird_type': 'broiler', 'breed': 'Cobb 500',
        'quantity': 1000, 'start_date': start.isoformat(),
    }, content_type=JSON)
    check('flock create -> 201', r.status_code == 201, r.content[:200])
    flock_id = r.json()['id']
    check('age_days computed from start_date', r.json()['age_days'] == 5, r.json())

    # 2. Feed chart / stage lookup.
    r = c.get(f'/api/farmers/flocks/{flock_id}/feed-chart/')
    check('feed-chart -> 200', r.status_code == 200, r.content[:300])
    body = r.json()
    check('feed-chart matches a starter-stage guideline for a 5-day-old broiler',
          body['current_guideline'] is not None and '0-10' in body['current_guideline']['stage_label'],
          body.get('current_guideline'))
    check('feed-chart includes the full guideline timeline for the bird type',
          len(body['guidelines']) >= 3, body['guidelines'])
    check('feed-chart carries a general-guidance disclaimer', 'not veterinary' in body['disclaimer'].lower())

    # 3. Flock events — mortality decrements current_quantity.
    r = c.post(f'/api/farmers/flocks/{flock_id}/events/', {
        'event_type': 'mortality', 'quantity': 20, 'event_date': date.today().isoformat(),
        'notes': 'Heat stress',
    }, content_type=JSON)
    check('mortality event -> 201', r.status_code == 201, r.content[:300])
    flock = Flock.objects.get(pk=flock_id)
    check('current_quantity decremented by mortality', flock.current_quantity == 980, flock.current_quantity)

    r = c.post(f'/api/farmers/flocks/{flock_id}/events/', {
        'event_type': 'sale', 'quantity': 10000, 'event_date': date.today().isoformat(),
    }, content_type=JSON)
    check('sale exceeding current bird count is rejected', r.status_code == 400, r.content[:200])

    r = c.post(f'/api/farmers/flocks/{flock_id}/events/', {
        'event_type': 'mortality', 'quantity': -5, 'event_date': date.today().isoformat(),
    }, content_type=JSON)
    check('negative quantity is rejected', r.status_code == 400, r.content[:200])

    r = c.get(f'/api/farmers/flocks/{flock_id}/events/')
    check('events are listed (immutable log)', r.status_code == 200 and len(r.json()['results']) == 1, r.content[:300])

    # 4. Whole-flock sale closes the flock.
    r = c.post(f'/api/farmers/flocks/{flock_id}/events/', {
        'event_type': 'sale', 'quantity': 980, 'event_date': date.today().isoformat(),
    }, content_type=JSON)
    check('selling the remaining birds -> 201', r.status_code == 201, r.content[:300])
    flock.refresh_from_db()
    check('flock auto-closes at 0 birds', flock.current_quantity == 0 and flock.status == 'closed', flock.status)

    # 5. Notification generation — idempotent same-day.
    fresh_start = date.today()
    r2 = c.post('/api/farmers/flocks/', {
        'batch_name': 'Batch-Notif-Test', 'bird_type': 'layer', 'breed': 'Lohmann',
        'quantity': 500, 'start_date': fresh_start.isoformat(),
    }, content_type=JSON)
    call_command('generate_feed_notifications')
    n1 = Notification.objects.filter(user=farmer, reference_type__in=(
        'feed_stage_upcoming', 'feed_daily_reminder')).count()
    check('notification command creates feeding notifications for an active flock', n1 > 0, n1)
    call_command('generate_feed_notifications')
    n2 = Notification.objects.filter(user=farmer, reference_type__in=(
        'feed_stage_upcoming', 'feed_daily_reminder')).count()
    check('re-running the same day does not duplicate notifications (idempotent)', n2 == n1, (n1, n2))

    # 6. Permission isolation.
    other = mk_farmer()
    oc = client_for(other)
    r = oc.get(f'/api/farmers/flocks/{flock_id}/events/')
    check("another farmer cannot read this farmer's flock events", r.status_code == 404, r.content[:200])
    r = oc.get(f'/api/farmers/flocks/{flock_id}/feed-chart/')
    check("another farmer cannot read this farmer's feed chart", r.status_code == 404, r.content[:200])

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed\n')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    run()
