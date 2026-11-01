"""Regression suite for the seed_platform_demo fix (idempotent, duplicate-farm safe).

Runs against a SCRATCH database only (refuses the main dev DB) and rolls every
scenario back, so it is repeatable and leaves nothing behind:

    POSTGRES_DB=featherflow_clean python scripts/test_seed_platform_demo.py

Scenarios
  A. clean slate: run 1/2/3, multiple farmers, no duplicate accounts/farms/products
  B. existing records: suspended demo user, edited farm with dependents, an
     unrelated farmer with several farms -> all preserved
  C. legacy exact-duplicate farms (the original crash): seed succeeds 3x, creates
     nothing, dedupe_farms removes only empty duplicates, then the unique index
     can be (re)built and blocks new duplicates
"""
import io
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.core.management import call_command  # noqa: E402
from django.db import IntegrityError, connection, transaction  # noqa: E402

from farms.models import Farm, Shed  # noqa: E402
from farms.services import canonical_farm  # noqa: E402
from pharmacy.models import PharmacyMedicine  # noqa: E402
from profiles.models import AdminProfile, FarmerProfile  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
RASHED = 'farmer.rashed@example.com'
NASIMA = 'farmer.nasima@example.com'
OLD_PASSWORD_HASH = None


def check(name, cond, extra=''):
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f'  ok   {name}')
    else:
        FAIL += 1
        print(f'  FAIL {name}  {extra}')


class Rollback(Exception):
    pass


def seed():
    out = io.StringIO()
    call_command('seed_platform_demo', stdout=out)
    return out.getvalue()


def counts():
    return {
        'users': User.objects.count(),
        'farms': Farm.objects.count(),
        'farmer_profiles': FarmerProfile.objects.count(),
        'medicines': PharmacyMedicine.objects.count(),
        'admin_profiles': AdminProfile.objects.count(),
        'roles': Role.objects.count(),
    }


def no_dupes():
    with connection.cursor() as cur:
        cur.execute('select count(*) from (select lower(email) from users group by 1 having count(*)>1) t')
        emails = cur.fetchone()[0]
        cur.execute('select count(*) from (select farmer_id, lower(btrim(farm_name)) from farms '
                    'group by 1,2 having count(*)>1) t')
        farms = cur.fetchone()[0]
    from django.db.models import Count
    meds = (PharmacyMedicine.objects.exclude(legacy_record_id__isnull=True)
            .values('pharmacy_user_id', 'legacy_record_id').annotate(n=Count('id')).filter(n__gt=1).count())
    return emails, farms, meds


def fk_orphans():
    with connection.cursor() as cur:
        cur.execute('select count(*) from sheds s left join farms f on f.id=s.farm_id where f.id is null')
        return cur.fetchone()[0]


def scenario(fn):
    try:
        with transaction.atomic():
            fn()
            raise Rollback()
    except Rollback:
        pass


def a_clean_slate():
    print('\n== A. clean slate: three runs ==')
    check('demo accounts absent before the first run (scratch DB)',
          not User.objects.filter(email__in=[RASHED, NASIMA]).exists())
    base = counts()
    seed()
    c1 = counts()
    check('run 1 creates the demo data', c1['users'] > base['users'] and c1['farms'] == base['farms'] + 2, (base, c1))
    check('run 1: 2 farmers, one farm each', all(
        Farm.objects.filter(farmer__user__email=e).count() == 1 for e in (RASHED, NASIMA)))
    check('run 1: distinct farms for the two farmers',
          canonical_farm(FarmerProfile.objects.get(user__email=RASHED)).id
          != canonical_farm(FarmerProfile.objects.get(user__email=NASIMA)).id)
    seed()
    c2 = counts()
    check('run 2 succeeds and changes no row counts', c2 == c1, (c1, c2))
    seed()
    c3 = counts()
    check('run 3 succeeds and changes no row counts', c3 == c1, (c1, c3))
    check('no duplicate e-mails / farms / medicine products', no_dupes() == (0, 0, 0), no_dupes())
    check('catalogue seeded once (6 medicines for the verified pharmacy)',
          PharmacyMedicine.objects.filter(pharmacy_user__email='pharmacy.greenvet@example.com',
                                          legacy_record_id__startswith='PH-DEMO-').count() == 6)
    check('farmer profiles one per farmer', FarmerProfile.objects.filter(
        user__email__in=[RASHED, NASIMA]).count() == 2)
    check('pending demo accounts stay pending',
          User.objects.get(email='dr.pending.kabir@example.com').account_status == 'pending')


def d_phone_collision():
    print('\n== D. demo phone already owned by another account ==')
    owner = User(email='real.admin@example.com', phone='+8801711000606', full_name='Real Admin',
                 present_address='X', date_of_birth=date(1985, 1, 1), account_status='active',
                 is_verified=True, consent_terms=True)
    owner.set_password('x')
    owner.save()
    for i in (1, 2, 3):
        seed()
        check(f'run {i} succeeds although +8801711000606 is taken', True)
    check('the other account keeps its phone', User.objects.get(email='real.admin@example.com').phone == '+8801711000606')
    demo = User.objects.get(email='admin.pharmacy@example.com')
    check('demo account created once with a derived free phone', demo.phone != '+8801711000606'
          and User.objects.filter(email='admin.pharmacy@example.com').count() == 1)
    check('no duplicate accounts', no_dupes() == (0, 0, 0))


def b_existing_records():
    print('\n== B. existing records, dependents and suspended users ==')
    hashed = User.objects.make_random_password() if hasattr(User.objects, 'make_random_password') else 'x'
    u = User(email=RASHED, phone='+8801711000101', full_name='Real Rashed', present_address='Real Address',
             date_of_birth=date(1980, 2, 2), account_status='suspended', is_verified=False,
             consent_terms=True)
    u.set_password('RealPassword#1')
    u.save()
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u.roles.add(role)
    fp = FarmerProfile.objects.create(
        user=u, farm_name='Real Farm Name', owner_name='Real Rashed', farm_location='Real Address',
        farm_address='Real Address', farm_type='layer', number_of_birds=999, consent_data_collection=True)
    farm = Farm.objects.create(farmer=fp, farm_name='Real Farm Name', farm_type='layer', location='L', address='A',
                               is_active=True)
    shed = Shed.objects.create(farm=farm, shed_name='Real Shed', capacity=100)
    # An unrelated farmer with two legitimately different farms and a dependent.
    other = User(email='unrelated.farmer@example.com', phone='+8801799990001', full_name='Unrelated',
                 present_address='X', date_of_birth=date(1985, 1, 1), account_status='active',
                 is_verified=True, consent_terms=True)
    other.set_password('Whatever#1')
    other.save()
    ofp = FarmerProfile.objects.create(user=other, farm_name='Other A', owner_name='Unrelated',
                                       farm_location='X', farm_address='X', farm_type='broiler',
                                       consent_data_collection=True)
    of1 = Farm.objects.create(farmer=ofp, farm_name='Other A', location='X', address='X')
    of2 = Farm.objects.create(farmer=ofp, farm_name='Other B', location='X', address='X')
    oshed = Shed.objects.create(farm=of2, shed_name='Other shed', capacity=5)
    before_hash = User.objects.get(email=RASHED).password
    before = counts()
    for i in (1, 2, 3):
        seed()
        check(f'run {i} succeeds with existing records', True)
    after = User.objects.get(email=RASHED)
    check('suspended demo user stays suspended', after.account_status == 'suspended', after.account_status)
    check('real status/verification not overwritten', after.is_verified is False)
    check('real password not reset', after.password == before_hash)
    check('real name/address not overwritten', after.full_name == 'Real Rashed' and after.present_address == 'Real Address')
    fp.refresh_from_db()
    check('existing farmer profile data not overwritten', fp.farm_name == 'Real Farm Name'
          and fp.number_of_birds == 999 and fp.farm_type == 'layer')
    check('the existing farm is reused: still exactly one farm for the farmer',
          list(Farm.objects.filter(farmer=fp).values_list('id', flat=True)) == [farm.id])
    farm.refresh_from_db()
    check('existing farm not modified', farm.farm_name == 'Real Farm Name' and farm.farm_type == 'layer')
    check('dependent records still point at the same farm', Shed.objects.get(pk=shed.pk).farm_id == farm.id)
    check('no orphaned dependents', fk_orphans() == 0)
    check('unrelated farmer data intact',
          set(Farm.objects.filter(farmer=ofp).values_list('id', flat=True)) == {of1.id, of2.id}
          and Shed.objects.get(pk=oshed.pk).farm_id == of2.id
          and User.objects.get(email='unrelated.farmer@example.com').account_status == 'active')
    check('seed added the other demo accounts but no duplicates', no_dupes() == (0, 0, 0))
    after_counts = counts()
    check('only the missing demo rows were added (farms +1 for Nasima only)',
          after_counts['farms'] == before['farms'] + 1, (before, after_counts))
    check('canonical farm of the suspended farmer is the existing one', canonical_farm(fp).id == farm.id)


def c_legacy_duplicates():
    print('\n== C. legacy exact-duplicate farms (the original crash) ==')
    with connection.cursor() as cur:
        cur.execute('drop index if exists uq_farms_farmer_name')  # transactional in Postgres
    u = User(email=NASIMA, phone='+8801711000102', full_name='Nasima Akter', present_address='Mymensingh',
             date_of_birth=date(1990, 1, 1), account_status='suspended', is_verified=False, consent_terms=True)
    u.set_password('x')
    u.save()
    role, _ = Role.objects.get_or_create(name='farmer', defaults={'panel_type': 'farmer'})
    u.roles.add(role)
    fp = FarmerProfile.objects.create(user=u, farm_name='Shapla Layer Farm', owner_name='Nasima',
                                      farm_location='M', farm_address='M', farm_type='layer',
                                      consent_data_collection=True)
    dup_a = Farm.objects.create(farmer=fp, farm_name='Shapla Layer Farm', location='M', address='M',
                                created_at='2026-01-01T00:00:00Z')
    dup_b = Farm.objects.create(farmer=fp, farm_name='Shapla Layer Farm', location='M', address='M')
    Shed.objects.create(farm=dup_a, shed_name='S1', capacity=10)
    before_farms = Farm.objects.count()
    for i in (1, 2, 3):
        seed()
        check(f'run {i} succeeds despite exact-duplicate farms', True)
    check('seed created no extra farm for the duplicated farmer',
          Farm.objects.filter(farmer=fp).count() == 2)
    check('canonical farm is deterministic (dated + with dependents)', canonical_farm(fp).id == dup_a.id)
    check('suspended farmer stays suspended', User.objects.get(email=NASIMA).account_status == 'suspended')
    out = io.StringIO()
    call_command('dedupe_farms', stdout=out)
    check('dry-run reports the duplicate and deletes nothing',
          'DUPLICATE' in out.getvalue() and 'would delete' in out.getvalue()
          and Farm.objects.filter(farmer=fp).count() == 2, out.getvalue())
    out = io.StringIO()
    call_command('dedupe_farms', '--apply', stdout=out)
    check('--apply deletes only the empty duplicate', Farm.objects.filter(farmer=fp).count() == 1
          and Farm.objects.filter(pk=dup_a.pk).exists() and not Farm.objects.filter(pk=dup_b.pk).exists(), out.getvalue())
    check('the surviving farm keeps its dependent', Shed.objects.filter(farm=dup_a).count() == 1 and fk_orphans() == 0)

    # Both duplicates have dependents -> nothing is deleted or merged.
    dup_c = Farm.objects.create(farmer=fp, farm_name='shapla layer farm ', location='M', address='M')
    Shed.objects.create(farm=dup_c, shed_name='S2', capacity=10)
    out = io.StringIO()
    call_command('dedupe_farms', '--apply', stdout=out)
    check('duplicate WITH dependents is never deleted (reported for review)',
          Farm.objects.filter(pk=dup_c.pk).exists() and 'REVIEW' in out.getvalue(), out.getvalue())
    try:
        with transaction.atomic():
            with connection.cursor() as cur:
                cur.execute('create unique index uq_farms_farmer_name on farms (farmer_id, lower(btrim(farm_name)))')
        built = True
    except IntegrityError:
        built = False
    check('unique index cannot be built while a reviewed duplicate remains (safe failure)', built is False)
    Shed.objects.filter(farm=dup_c).delete()
    dup_c.delete()
    with connection.cursor() as cur:
        cur.execute('create unique index uq_farms_farmer_name on farms (farmer_id, lower(btrim(farm_name)))')
    try:
        with transaction.atomic():
            Farm.objects.create(farmer=fp, farm_name='SHAPLA LAYER FARM', location='M', address='M')
        blocked = False
    except IntegrityError:
        blocked = True
    check('after cleanup the unique index blocks new exact duplicates (case-insensitive)', blocked)
    seed()
    check('seed still succeeds with the index in place', True)
    check('no duplicates anywhere', no_dupes() == (0, 0, 0), no_dupes())


def main():
    name = connection.settings_dict['NAME']
    if name == 'featherflow':
        print('REFUSING to run against the main dev database; use POSTGRES_DB=featherflow_clean')
        sys.exit(2)
    with connection.cursor() as cur:
        cur.execute("select count(*) from pg_indexes where indexname='uq_farms_farmer_name'")
        if not cur.fetchone()[0]:
            print('apply backend/farms_natural_key_extension.sql to the scratch DB first')
            sys.exit(2)
    print(f'scratch database: {name}')
    for fn in (a_clean_slate, b_existing_records, c_legacy_duplicates, d_phone_collision):
        scenario(fn)
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
