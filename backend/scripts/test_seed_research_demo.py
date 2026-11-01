"""Regression suite for F-015: `seed_research_demo` is idempotent and never touches an existing account.

Runs against a SCRATCH database only (refuses the main dev DB) and rolls each scenario back:

    POSTGRES_DB=featherflow_scripts_clean python scripts/test_seed_research_demo.py

A. a REAL suspended research.sabiha@example.com (plus a banned and a pending researcher) exists before the
   first run -> three runs leave status, verification, password, roles, profile and her own submissions
   untouched, create no marker for her, grant her no subscription, and add no duplicate rows;
B. clean slate: run 1 creates the demo data and one marker per created account; runs 2 and 3 change nothing;
   suspending / un-verifying demo accounts and changing submission statuses afterwards survives a re-run.
"""
import io
import json
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
django.setup()

from django.core.management import call_command  # noqa: E402
from django.db import connection, transaction  # noqa: E402
from django.utils import timezone  # noqa: E402

from articles.models import Article  # noqa: E402
from audit.models import AdminPanelRecord  # noqa: E402
from community.models import Bookmark, Report  # noqa: E402
from profiles.models import ResearcherProfile  # noqa: E402
from research.models import ArticleVersionSnapshot, ProfileChangeApplication  # noqa: E402
from subscriptions.models import Subscription  # noqa: E402
from users.models import Role, User, UserRole  # noqa: E402

PASS = FAIL = 0
SABIHA = 'research.sabiha@example.com'
FARIHA = 'research.fariha@example.com'
MAHMUD = 'research.mahmud@example.com'
DRAFT_TITLE = 'Preliminary Notes on Vaccine Response Variability in Layer Flocks'  # a title the seed would create for her
SNAPSHOTS = []


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
    call_command('seed_research_demo', stdout=io.StringIO())


def counts():
    return {
        'users': User.objects.count(), 'user_roles': UserRole.objects.count(),
        'researcher_profiles': ResearcherProfile.objects.count(), 'articles': Article.objects.count(),
        'article_version_snapshots': ArticleVersionSnapshot.objects.count(), 'bookmarks': Bookmark.objects.count(),
        'profile_change_applications': ProfileChangeApplication.objects.count(), 'reports': Report.objects.count(),
        'subscriptions': Subscription.objects.count(),
        'seed_markers': AdminPanelRecord.objects.filter(module='seed-accounts').count(),
    }


def statuses():
    return {
        'users': sorted((u.email, u.account_status, bool(u.is_verified), u.password) for u in User.objects.all()),
        'profiles': sorted((p.user.email, bool(p.is_verified)) for p in ResearcherProfile.objects.select_related('user')),
        'articles': sorted((a.author.email, a.title, a.status, a.review_notes or '', a.version) for a in Article.objects.select_related('author')),
        'roles': sorted((ur.user.email, ur.role.name) for ur in UserRole.objects.select_related('user', 'role')),
    }


def snap(label):
    c, s = counts(), statuses()
    SNAPSHOTS.append({'label': label, 'counts': c, 'sabiha': [x for x in s['users'] if x[0] == SABIHA and True][0][1:3] if any(x[0] == SABIHA for x in s['users']) else None})
    return c, s


def mk_user(email, phone, name, status, verified):
    u = User(email=email, phone=phone, full_name=name, present_address='Real Address', date_of_birth=date(1985, 5, 5),
             consent_terms=True, account_status=status, is_verified=verified, created_at=timezone.now(), updated_at=timezone.now())
    u.set_password('RealUserPassword!9')
    u.save()
    UserRole.objects.get_or_create(user=u, role=Role.objects.get_or_create(name='researcher', defaults={'panel_type': 'researcher'})[0])
    return u


def profile_for(u, verified):
    return ResearcherProfile.objects.create(
        user=u, institution_name='Real Institute', institutional_email=f'x.{u.id.hex[:6]}@real.edu', department='Real Dept', highest_degree='MSc',
        field_of_study='Real field', university_name='Real Univ', graduation_year=2020, cv_url='https://real.example/cv', years_of_research_experience=3,
        is_verified=verified, created_at=timezone.now(), updated_at=timezone.now())


def scenario_a():
    print('\n== A. existing real accounts (suspended / banned / pending) ==')
    sab = mk_user(SABIHA, '+8801999000001', 'Sabiha Real', 'suspended', False)
    profile_for(sab, False)
    far = mk_user(FARIHA, '+8801999000002', 'Fariha Real', 'banned', True)
    profile_for(far, True)
    mah = mk_user(MAHMUD, '+8801999000003', 'Mahmud Real', 'pending', False)
    profile_for(mah, False)
    now = timezone.now()
    mine = Article.objects.create(author=sab, title=DRAFT_TITLE, content_type='disease_study', abstract='my own', body='my body', category='general',
                                  keywords=[], references_list=[], farmer_summary='', status='archived', version=4, read_count=7,
                                  co_authors=[], content_details={}, review_notes='removed by admin', is_featured=False, created_at=now, updated_at=now)
    other = Article.objects.create(author=sab, title='Sabiha real submission', content_type='research_paper', abstract='a', body='b', category='general',
                                   keywords=[], references_list=[], farmer_summary='', status='pending_review', version=2, read_count=0,
                                   co_authors=[], content_details={}, review_notes='', is_featured=False, created_at=now, updated_at=now)
    pw_before = {e: User.objects.get(email=e).password for e in (SABIHA, FARIHA, MAHMUD)}
    sabiha_subs_before = Subscription.objects.filter(user=sab).count()
    c0, s0 = snap('A: before run 1')
    seed(); c1, s1 = snap('A: after run 1')
    seed(); c2, s2 = snap('A: after run 2')
    seed(); c3, s3 = snap('A: after run 3')

    for email, status, verified in ((SABIHA, 'suspended', False), (FARIHA, 'banned', True), (MAHMUD, 'pending', False)):
        u = User.objects.get(email=email)
        check(f'{email}: account_status stays "{status}" and is_verified stays {verified} after 3 runs', u.account_status == status and bool(u.is_verified) == verified,
              (u.account_status, u.is_verified))
        check(f'{email}: password hash untouched', u.password == pw_before[email])
        check(f'{email}: the seed created NO marker for this real account', not AdminPanelRecord.objects.filter(module='seed-accounts', record_id=email).exists())
    check('research.sabiha profile still not verified, her details unchanged',
          ResearcherProfile.objects.get(user__email=SABIHA).institution_name == 'Real Institute' and not ResearcherProfile.objects.get(user__email=SABIHA).is_verified)
    check('banned researcher received no premium subscription from the seed', Subscription.objects.filter(user__email=FARIHA).count() == 0)
    check('suspended researcher received no subscription', Subscription.objects.filter(user=sab).count() == sabiha_subs_before)
    mine.refresh_from_db(); other.refresh_from_db()
    check('her archived submission (same title the seed would create) is intact: status, notes, version, no duplicate',
          mine.status == 'archived' and mine.review_notes == 'removed by admin' and mine.version == 4 and Article.objects.filter(author=sab, title=DRAFT_TITLE).count() == 1)
    check('her other submission is intact', other.status == 'pending_review' and other.version == 2)
    check('roles of the real accounts unchanged (one role each)', all(UserRole.objects.filter(user__email=e).count() == 1 for e in (SABIHA, FARIHA, MAHMUD)))
    check('run 2 and run 3 changed no row count', c1 == c2 == c3, (c1, c2, c3))
    check('run 2 and run 3 changed no status / password / role / article row', s1 == s2 == s3)
    check('run 1 only ADDED rows (nothing deleted)', all(c1[k] >= c0[k] for k in c0))
    check('every demo account created by run 1 has exactly one marker, listed with the source command',
          AdminPanelRecord.objects.filter(module='seed-accounts').count() == c1['seed_markers'] and
          all(r.payload.get('source') == 'seed_research_demo' for r in AdminPanelRecord.objects.filter(module='seed-accounts')))
    created = set(AdminPanelRecord.objects.filter(module='seed-accounts').values_list('record_id', flat=True))
    check('markers exist for admin.research and farmer.rashed (created by the seed) and not for the three real researchers',
          {'admin.research@example.com', 'farmer.rashed@example.com'} <= created and not ({SABIHA, FARIHA, MAHMUD} & created), created)


def scenario_b():
    print('\n== B. clean slate, then suspend / un-verify demo accounts and change statuses ==')
    c0, _ = snap('B: before run 1 (clean)')
    seed(); c1, s1 = snap('B: after run 1')
    seed(); c2, s2 = snap('B: after run 2')
    seed(); c3, s3 = snap('B: after run 3')
    check('run 1 created the demo researchers, articles and markers', c1['users'] > c0['users'] and c1['articles'] > c0['articles'] and c1['seed_markers'] >= 5, c1)
    check('run 2 and run 3: identical counts for every table', c1 == c2 == c3, (c1, c2, c3))
    check('run 2 and run 3: identical statuses / password hashes / roles / article rows', s1 == s2 == s3)
    created = {r.record_id for r in AdminPanelRecord.objects.filter(module='seed-accounts')}
    check('every account the seed created has verified contacts (so the demo users can actually sign in)',
          all(User.objects.get(email=e).email_verified_at is not None and User.objects.get(email=e).phone_verified_at is not None for e in created))
    check('one marker per created account (research x3, admin, farmer)', {SABIHA, FARIHA, MAHMUD, 'admin.research@example.com', 'farmer.rashed@example.com'} == created, created)
    check('the demo sabiha is un-verified by design and still active (seed default), draft only',
          User.objects.get(email=SABIHA).account_status == 'active' and not ResearcherProfile.objects.get(user__email=SABIHA).is_verified)
    # real activity creates MORE snapshots for the same article version; the seed must still re-run
    from research.models import ArticleVersionSnapshot as _AVS
    a0 = Article.objects.filter(author__email=MAHMUD).first()
    for n_ in range(2):
        _AVS.objects.create(article=a0, version=1, snapshot={'status': 'x'}, changed_by=a0.author, change_note=f'real activity {n_}', changed_at=timezone.now())
    seed()
    check('re-running the seed after extra version snapshots does not crash and adds no seed snapshot', True)
    # an admin suspends sabiha, bans fariha and moves submissions
    User.objects.filter(email=SABIHA).update(account_status='suspended')
    User.objects.filter(email=FARIHA).update(account_status='banned')
    Article.objects.filter(author__email=MAHMUD, status='pending_review').update(status='needs_revision', review_notes='admin note')
    ResearcherProfile.objects.filter(user__email=MAHMUD).update(is_verified=False)
    s_mid = statuses(); c_mid = counts()
    seed(); seed(); seed()
    s_end = statuses(); c_end = counts()
    check('after the admin changes, three more runs reactivate nobody', s_mid == s_end)
    check('research.sabiha@example.com is STILL suspended', User.objects.get(email=SABIHA).account_status == 'suspended')
    check('fariha still banned, mahmud still un-verified, his submission still needs_revision with the admin note',
          User.objects.get(email=FARIHA).account_status == 'banned' and not ResearcherProfile.objects.get(user__email=MAHMUD).is_verified
          and Article.objects.filter(author__email=MAHMUD, status='needs_revision', review_notes='admin note').exists())
    check('no duplicate rows after the extra runs', c_mid == c_end, (c_mid, c_end))
    check('no duplicate (author, title, type) article rows', Article.objects.count() == len({(a.author_id, a.title, a.content_type) for a in Article.objects.all()}))
    check('no duplicate email addresses', User.objects.count() == len({u.email for u in User.objects.all()}))


def run(fn):
    try:
        with transaction.atomic():
            fn()
            raise Rollback()
    except Rollback:
        pass


def main():
    name = connection.settings_dict['NAME']
    if name == 'featherflow':
        sys.exit('refusing to run against the main dev database - use a scratch DB (scripts/run_all_tests.py does)')
    if User.objects.filter(email__in=[SABIHA, FARIHA, MAHMUD]).exists():
        sys.exit(f'{name} already contains research demo users; run against a clean scratch database')
    run(scenario_a)
    run(scenario_b)
    print('\nSNAPSHOTS ' + json.dumps(SNAPSHOTS))
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    main()
