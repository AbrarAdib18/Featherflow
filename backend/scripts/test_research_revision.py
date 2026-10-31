"""NF-5: Research Admin "Request revision" - eligibility, mandatory reason, RBAC, notification, history.

    python scripts/test_research_revision.py

Throw-away accounts/content (`nf5+`), self-cleaning. Run against a scratch DB (scripts/run_all_tests.py does).
"""
import os
import sys
from datetime import date

import django

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'featherflow_backend.settings')
os.environ.setdefault('EMAIL_BACKEND', 'django.core.mail.backends.locmem.EmailBackend')
for key in ('READ', 'WRITE', 'EXPORT', 'POLL'):
    os.environ.setdefault(f'THROTTLE_ADMIN_{key}', '100000/min')
django.setup()

from django.conf import settings as dj_settings  # noqa: E402
if 'testserver' not in dj_settings.ALLOWED_HOSTS:
    dj_settings.ALLOWED_HOSTS.append('testserver')

from django.test import Client  # noqa: E402
from django.utils import timezone  # noqa: E402
from rest_framework_simplejwt.tokens import RefreshToken  # noqa: E402

from articles.models import Article  # noqa: E402
from audit.models import ActivityLog  # noqa: E402
from notifications.models import Notification  # noqa: E402
from profiles.models import AdminProfile, ResearcherProfile  # noqa: E402
from research.models import ArticleVersionSnapshot  # noqa: E402
from users.models import Role, User  # noqa: E402

PASS = FAIL = 0
PREFIX = 'nf5+'
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
    arts = Article.objects.filter(author__in=users)
    ArticleVersionSnapshot.objects.filter(article__in=arts).delete()
    Notification.objects.filter(user__in=users).delete()
    arts.delete()
    AdminProfile.objects.filter(user__in=users).delete()
    ResearcherProfile.objects.filter(user__in=users).delete()
    users.delete()
    Role.objects.filter(name='nf5_viewer').delete()


_n = [0]


def mk(tag, role_name, perms=None, admin=False):
    _n[0] += 1
    role = Role.objects.filter(name=role_name).first()
    if role is None:
        role = Role.objects.create(name=role_name, panel_type='admin', permissions=perms or {}, tier_level=3)
    u = User.objects.create_user(
        email=f'{PREFIX}{tag}@example.com', password='Test1234!', phone=f'0194{os.getpid() % 1000:03d}{_n[0]:04d}',
        full_name=tag.title(), date_of_birth=date(1990, 1, 1), present_address='Dhaka', consent_terms=True,
        account_status='active', is_verified=True)
    u.roles.add(role)
    if admin:
        AdminProfile.objects.update_or_create(user=u, defaults=dict(
            admin_role=role, job_title='Tester', department='QA', start_date=date(2024, 1, 1),
            admin_sub_role=(role_name.replace('admin_', '') if role_name.startswith('admin_') else 'support'), approval_status='approved', is_active=True,
            is_suspended=False, internal_approval_by_founder_hr=True))
    return u


def client_for(user):
    c = Client()
    c.defaults['HTTP_AUTHORIZATION'] = f'Bearer {RefreshToken.for_user(user).access_token}'
    return c


def mk_article(author, status, title):
    now = timezone.now()
    return Article.objects.create(
        author=author, title=title, content_type='research_paper', abstract='abs', body='body', category='general',
        keywords=[], references_list=[], farmer_summary='', status=status, version=1, read_count=0,
        co_authors=[], content_details={}, review_notes='', is_featured=False, created_at=now, updated_at=now)


def main():
    cleanup()
    author = mk('author', 'researcher')
    now = timezone.now()
    ResearcherProfile.objects.create(
        user=author, institution_name='Test Univ', institutional_email='a@test.edu', department='Vet', highest_degree='PhD',
        field_of_study='Poultry', university_name='Test Univ', graduation_year=2015, cv_url='x', years_of_research_experience=5,
        is_verified=True, created_at=now, updated_at=now)
    research_admin = mk('radmin', 'admin_research', admin=True)
    content_admin = mk('cadmin', 'admin_content', admin=True)
    doctor_admin = mk('dadmin', 'admin_doctor', admin=True)
    viewer = mk('viewer', 'nf5_viewer', perms={'research': ['view'], 'articles': ['view']}, admin=True)
    farmer = mk('farmer', 'farmer')
    ra, ca, da, vc, fc, authc, anon = (client_for(research_admin), client_for(content_admin), client_for(doctor_admin),
                                       client_for(viewer), client_for(farmer), client_for(author), Client())

    pending = mk_article(author, 'pending_review', 'nf5 pending paper')
    url = lambda a: f'/api/admin-panel/research-papers/{a.id}/'  # noqa: E731
    hist = lambda a: f'/api/admin-panel/articles/{a.id}/revision-history/'  # noqa: E731

    print('\n== reason is mandatory ==')
    for label, notes in (('missing', None), ('empty', ''), ('blank spaces', '   ')):
        body = {'action': 'request_revision'}
        if notes is not None:
            body['review_notes'] = notes
        r = ra.patch(url(pending), body, content_type=JSON)
        check(f'{label} reason -> 400 revision_reason_required', r.status_code == 400 and r.json().get('code') == 'revision_reason_required', r.content[:160])
    r = ra.patch(url(pending), {'action': 'request_revision', 'review_notes': 'x' * 2001}, content_type=JSON)
    check('over-long reason -> 400', r.status_code == 400 and r.json().get('code') == 'revision_reason_too_long')
    pending.refresh_from_db()
    check('rejected requests left the submission untouched', pending.status == 'pending_review' and pending.review_notes == '')
    check('no notification or snapshot from rejected requests',
          not Notification.objects.filter(user=author).exists() and not ArticleVersionSnapshot.objects.filter(article=pending).exists())

    print('\n== permissions (same gate as the UI) ==')
    body = {'action': 'request_revision', 'review_notes': 'Add the sample size.'}
    check('anonymous -> 401', anon.patch(url(pending), body, content_type=JSON).status_code == 401)
    check('farmer -> 403', fc.patch(url(pending), body, content_type=JSON).status_code == 403)
    check('the author cannot send their own paper back -> 403', authc.patch(url(pending), body, content_type=JSON).status_code == 403)
    check('doctor admin (no research permission) -> 403', da.patch(url(pending), body, content_type=JSON).status_code == 403)
    r = vc.patch(url(pending), body, content_type=JSON)
    check('admin with only "view" cannot request revision -> 403', r.status_code == 403 and r.json().get('code') == 'forbidden_module_action', r.content[:160])
    pending.refresh_from_db()
    check('unauthorized attempts changed nothing', pending.status == 'pending_review')

    print('\n== eligibility ==')
    for status in ('draft', 'published', 'archived', 'needs_revision'):
        other = mk_article(author, status, f'nf5 {status}')
        r = ra.patch(url(other), body, content_type=JSON)
        check(f'{status} -> 409 not_revision_eligible', r.status_code == 409 and r.json().get('code') == 'not_revision_eligible', r.content[:160])
        other.refresh_from_db()
        check(f'{status} content unchanged', other.status == status and other.review_notes == '')

    print('\n== successful request ==')
    r = ra.patch(url(pending), body, content_type=JSON)
    check('research admin -> 200, status "Needs Revision", reason echoed',
          r.status_code == 200 and r.json()['status'] == 'Needs Revision' and r.json()['review_notes'] == body['review_notes'], r.content[:200])
    pending.refresh_from_db()
    check('DB: needs_revision + review_notes', pending.status == 'needs_revision' and pending.review_notes == body['review_notes'])
    notes = list(Notification.objects.filter(user=author))
    check('exactly one notification to the author naming the reason',
          len(notes) == 1 and 'Revision requested' in notes[0].title and body['review_notes'] in notes[0].body, [(n.title, n.body) for n in notes])
    check('activity log entry written', ActivityLog.objects.filter(user=research_admin).exists())
    snaps = list(ArticleVersionSnapshot.objects.filter(article=pending))
    check('one revision snapshot with admin, reason and timestamp',
          len(snaps) == 1 and snaps[0].changed_by_id == research_admin.id and snaps[0].snapshot.get('review_notes') == body['review_notes'] and snaps[0].changed_at is not None)
    r = ra.patch(url(pending), {'action': 'request_revision', 'review_notes': 'second request'}, content_type=JSON)
    check('a second request on the same submission is rejected (409) and does not overwrite the first reason',
          r.status_code == 409 and Article.objects.get(pk=pending.pk).review_notes == body['review_notes'])
    check('still only one notification', Notification.objects.filter(user=author).count() == 1)

    print('\n== content admin has the same ability; history endpoint ==')
    p2 = mk_article(author, 'pending_review', 'nf5 pending 2')
    r = ca.patch(url(p2), {'action': 'request_revision', 'review_notes': 'Cite your sources.'}, content_type=JSON)
    check('content admin -> 200', r.status_code == 200)
    r = ra.get(hist(pending))
    j = r.json()
    check('history: 200 with status, reason and entries',
          r.status_code == 200 and j['status'] == 'Needs Revision' and j['review_notes'] == body['review_notes'] and j['can_request_revision'] is False and len(j['history']) == 1, j)
    e = j['history'][0]
    check('history entry has author-of-change, time, note and reason',
          e['by'] and e['at'] and e['kind'] == 'revision_requested' and e['reason'] == body['review_notes'], e)
    j2 = ra.get(hist(mk_article(author, 'pending_review', 'nf5 pending 3'))).json()
    check('a pending item says it can be sent back', j2['can_request_revision'] is True and j2['history'] == [])
    check('history: anonymous 401', anon.get(hist(pending)).status_code == 401)
    check('history: farmer 403', fc.get(hist(pending)).status_code == 403)
    check('history: doctor admin 403', da.get(hist(pending)).status_code == 403)
    check('history: view-only admin 200', vc.get(hist(pending)).status_code == 200)
    check('history: unknown id 404', ra.get('/api/admin-panel/articles/00000000-0000-0000-0000-000000000000/revision-history/').status_code == 404)

    print('== author resubmits -> eligible again ==')
    # The author-side resubmit endpoint sits behind a researcher subscription gate covered elsewhere;
    # the state it produces (pending_review again) is set directly.
    Article.objects.filter(pk=pending.pk).update(status='pending_review')
    r = ra.patch(url(pending), {'action': 'request_revision', 'review_notes': 'Round two.'}, content_type=JSON)
    check('a second round is accepted (200)', r.status_code == 200, r.content[:120])
    check('history now has two revision requests, newest first',
          [h['reason'] for h in ra.get(hist(pending)).json()['history'] if h['kind'] == 'revision_requested'] == ['Round two.', body['review_notes']])
    check('the author has three revision notifications (two papers, one second round)', Notification.objects.filter(user=author, title__startswith='Revision requested').count() == 3)

    cleanup()
    print(f'\n{PASS} passed, {FAIL} failed')
    sys.exit(1 if FAIL else 0)


if __name__ == '__main__':
    try:
        main()
    finally:
        cleanup()
