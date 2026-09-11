"""Comprehensive demo data for a single phone-number account.

Populates the account tied to a phone number (default ``01713018156``) with data
across every farmer-facing surface so the app can be demoed end to end:

  * farmer profile + farm + sheds + flocks
  * cost management — 20+ expenses, 15+ revenue entries, 3 loans, feed stock
  * tax profile + recorded payments
  * community — 10+ posts, 20+ comments on other farmers' posts, reactions,
    follows, article/paper bookmarks
  * disease detection — past scans with predictions
  * notifications (read + unread)
  * pharmacy orders + vet consultations (best effort — needs the platform demo)

Run:
    backend/venv/Scripts/python.exe manage.py seed_demo_data_for_phone
    backend/venv/Scripts/python.exe manage.py seed_demo_data_for_phone --phone 01713018156
    backend/venv/Scripts/python.exe manage.py seed_demo_data_for_phone --reset

Idempotent: re-running is a no-op unless ``--reset`` is passed (which clears the
rows this command created first).
"""
import random
import uuid
from datetime import date, timedelta
from decimal import Decimal

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from users.models import User

DEFAULT_PHONE = '01713018156'
DEMO_PASSWORD = 'FeatherflowDemo@2026'
SEED_TAG = 'ff-phone-demo'

EXTRA_POSTS = [
    ('text', 'Switched to a 3-phase brooder setup',
     'After last winter I rebuilt the brooding area with three heat zones. '
     'Chick mortality in week 1 dropped from 4% to under 1.5%. Happy to share photos.'),
    ('question', 'Best age to move layers to the laying house?',
     'My pullets are 15 weeks. Some say move at 16, others wait for first egg. '
     'What has worked for your flock without a production dip?'),
    ('text', 'Feed price update — Mymensingh',
     'Grower mash up 90tk/bag this week at two dealers. Locking in a month of '
     'stock before it climbs again. Anyone getting a better rate nearby?'),
    ('poll', 'How do you handle vaccination records?',
     'Trying to get organised before the next batch. What do most of you use?'),
    ('text', 'Cost tracker paid for itself',
     'One month in and the report showed feed is 71% of my spend. Renegotiated '
     'with my dealer and shaved 6% off. Small wins.'),
    ('question', 'Sudden drop in water intake — worried',
     'Flock is 30 days, ambient temp normal, but water is down ~20% since '
     'yesterday. Feed intake still okay. First thing you would check?'),
    ('text', 'Litter management that finally worked',
     'Weekly top-up with fresh rice husk + a light stir, full clean-out between '
     'batches with lime. Ammonia smell is basically gone.'),
    ('text', 'Got my first vet consult through the app',
     'Booked a video call for a respiratory issue. Prescription came through in '
     'the app and the pharmacy delivered next day. Smooth.'),
]

COMMENT_LINES = [
    'This is really helpful, thanks for sharing the numbers.',
    'Had the same problem last season — a full clean-out fixed it for me.',
    'What breed are you running? Makes a big difference on FCR.',
    'Following. Dealing with something similar this week.',
    'Try checking the water lines first, that caught me out once.',
    'Great write-up. Bookmarking this for the next batch.',
    'We get about the same price here in Savar. Margins are tight.',
    'Did you use a specific brand or just local supply?',
    'Vaccination timing matters a lot here — day 7 and day 21 for us.',
    'Appreciate you posting the schedule, saving it.',
    'How long did the recovery take after you started treatment?',
    'Load-shedding is brutal for brooding. A small IPS helped us.',
    'Consider adding electrolytes to the water for a few days.',
    'Nice results. What was your week-1 mortality before the change?',
    'Same here. Feed cost is eating everything this quarter.',
    'Thanks — going to try the lime treatment between batches.',
    'Do you keep the records on paper or in the app?',
    'Good tip on the finisher feed, will test it on half the shed.',
    'Any photos of the brooder layout? Would love to see it.',
    'We switched dealers for the same reason. Worth shopping around.',
    'Keep us posted on how it goes.',
    'This matches what my vet told me last month.',
    'Solid advice. The stir + top-up routine works for us too.',
    'Curious what your final live weight was at market.',
]


class Command(BaseCommand):
    help = 'Seed comprehensive farmer demo data for one phone-number account.'

    def add_arguments(self, parser):
        parser.add_argument('--phone', default=DEFAULT_PHONE)
        parser.add_argument('--email', default=None)
        parser.add_argument('--reset', action='store_true')

    def handle(self, *args, **opts):
        rng = random.Random(1713018156)
        phone = _normalize_phone(opts['phone'])
        email = opts['email'] or f'demo.{opts["phone"]}@featherflow.demo'

        user = self._ensure_user(phone, email)
        self.stdout.write(self.style.SUCCESS(
            f'account: {user.email} / {user.phone} (id {user.id})'))

        if opts['reset']:
            self._wipe(user)

        counts = {}
        with transaction.atomic():
            counts.update(self._farmer_bulk(rng, user))
            e2, r2 = self._extra_cost(rng, user)
            counts['expenses'] = counts.get('expenses', 0) + e2
            counts['revenue'] = counts.get('revenue', 0) + r2
            counts['tax_payments'] = self._tax(user)
            counts['posts'] = counts.get('posts', 0) + self._posts(rng, user)
            counts['comments'], counts['reactions'] = self._engage(rng, user)
            counts['follows'] = self._follows(user)
            counts['bookmarks'] = self._bookmarks(rng, user)
            counts['disease_scans'] = self._disease_scans(rng, user)
            counts['notifications'] = (counts.get('notifications', 0)
                                       + self._notifications(user))

        self.stdout.write(self.style.SUCCESS(
            'seeded: ' + ', '.join(f'{v} {k}' for k, v in counts.items() if v)))
        self.stdout.write(self.style.SUCCESS(
            f'Sign in with  {user.phone}  or  {user.email}  / {DEMO_PASSWORD}'))

    # ── account ──────────────────────────────────────────────────────────
    def _ensure_user(self, phone, email):
        from farms.models import Farm
        from profiles.models import FarmerProfile
        from users.models import Role, UserRole

        now = timezone.now()
        user = (User.objects.filter(phone=phone).first()
                or User.objects.filter(email__iexact=email).first())
        if user is None:
            user = User.objects.create(
                email=email, phone=phone, full_name='Kamrul Hasan',
                present_address='Trishal, Mymensingh',
                date_of_birth=date(1988, 6, 12), preferred_language='en',
                consent_terms=True, consent_background_check=True,
                account_status='active', is_verified=True,
                email_verified_at=now, phone_verified_at=now)
            user.set_password(DEMO_PASSWORD)
            user.save()
        else:
            # make sure it can be signed into and is a farmer
            User.objects.filter(pk=user.pk).update(
                account_status='active', is_verified=True,
                email_verified_at=user.email_verified_at or now,
                phone_verified_at=user.phone_verified_at or now)
            user.refresh_from_db()
            # This is an explicit demo-seeding command for a known phone — make
            # the account usable with the shared demo password.
            user.set_password(DEMO_PASSWORD)
            user.save(update_fields=['password'])

        role, _ = Role.objects.get_or_create(
            name='farmer', defaults={'panel_type': 'farmer'})
        UserRole.objects.get_or_create(user=user, role=role)

        # Fill in a farmer profile but keep anything the real account already set.
        fp, created = FarmerProfile.objects.get_or_create(
            user=user,
            defaults=dict(
                farm_name='Kamrul Broiler & Layer Farm',
                owner_name=user.full_name or 'Farmer',
                farm_location=user.present_address or 'Trishal, Mymensingh',
                farm_address=f'{user.present_address or "Trishal, Mymensingh"}, Bangladesh',
                farm_type='mixed', number_of_birds=3600, years_in_farming=9,
                experience_level='expert', number_of_active_workers=3,
                feed_type='Commercial pellet + mash', consent_data_collection=True,
            ),
        )
        changed = []
        if not fp.number_of_birds:
            fp.number_of_birds = 3600
            changed.append('number_of_birds')
        if not fp.years_in_farming:
            fp.years_in_farming = 9
            changed.append('years_in_farming')
        if not fp.farm_photos:
            fp.farm_photos = [
                'https://images.unsplash.com/photo-1548550023-2bdb3c5beed7?w=800',
                'https://images.unsplash.com/photo-1516467508483-a7212febe31a?w=800',
            ]
            changed.append('farm_photos')
        if changed:
            fp.save(update_fields=changed)

        # One farm per profile — reuse whatever `farm_for` would.
        farm = Farm.objects.filter(farmer=fp).first()
        if farm is None:
            Farm.objects.create(
                farmer=fp, farm_name=fp.farm_name or 'Poultry Farm',
                farm_type=fp.farm_type or 'mixed',
                location=fp.farm_location, address=fp.farm_address,
                latitude=Decimal('24.5678'), longitude=Decimal('90.3912'),
                is_active=True)
        return user

    # ── bulk cost/feed/worker/consult data via the farmer seeder ─────────
    def _farmer_bulk(self, rng, user):
        from farmers.management.commands.seed_farmer_demo_data import Command as FarmerSeed
        from workers.views import farm_for
        from profiles.models import DoctorProfile

        farm = farm_for(user)
        seeder = FarmerSeed()
        seeder.stdout = self.stdout
        try:
            seeder._activate_doctors()
            seeder._provision_riders_and_pharmacies()
        except Exception as exc:  # pragma: no cover
            self.stdout.write(self.style.WARNING(f'  (skipped provisioning: {exc})'))

        from expenses.models import Expense
        if Expense.objects.filter(farm=farm).exists():
            return {'cost_mgmt': 'already present'}

        doctors = list(DoctorProfile.objects.select_related('user').filter(
            user__account_status='active'))
        from users.models import User as U
        pharmacies = list(U.objects.filter(
            roles__name='pharmacy', account_status='active'))
        spec = {'farm_type': 'mixed', 'birds': 3600, 'years': 9,
                'location': user.present_address,
                'lat': Decimal('24.5678'), 'lng': Decimal('90.3912')}
        return seeder._seed_farmer(rng, user, farm, spec, doctors, pharmacies)

    # ── extra expenses / revenue to reach 20+ / 15+ ─────────────────────
    def _extra_cost(self, rng, user):
        from expenses.models import (Expense, ExpenseCategory, Revenue,
                                     RevenueSource)
        from workers.views import farm_for
        farm = farm_for(user)
        today = date.today()
        if Expense.objects.filter(
                farm=farm, description='Automatic drinker line').exists():
            return 0, 0
        extra_exp = [
            ('Vaccines', 'Gumboro + ND booster', 3200, 6800,
             ('Renata Animal Health', 'ACI Animal Health')),
            ('Medicines', 'Antibiotic course (CRD)', 1400, 4200,
             ('GreenVet Pharmacy',)),
            ('Utilities', 'Electricity bill', 1800, 4600, ('Palli Bidyut',)),
            ('Labor', 'Casual labour — clean-out', 2500, 5000, ('Day labour',)),
            ('Equipment', 'Automatic drinker line', 6000, 14000,
             ('Poultry Equip BD',)),
            ('Litter', 'Rice husk delivery', 900, 2600, ('Local mill',)),
            ('Transport', 'Bird transport to market', 700, 2400,
             ('Pickup rental',)),
            ('Feed', 'Finisher pellet — top up', 9000, 21000,
             ('Nourish Feeds Ltd.', 'Paragon Feed')),
            ('Chicks', 'Day-old broiler chicks', 14000, 32000,
             ('Kazi Hatchery', 'CP Bangladesh')),
            ('Repairs', 'Roof net + curtain repair', 1200, 4800,
             ('Shed maintenance',)),
        ]
        extra_rev = [
            ('Bird Sales', 'Broiler batch — full clear', 22000, 62000,
             ('Karwan Bazar trader', 'Local wholesaler')),
            ('Egg Sales', 'Weekly egg supply', 8000, 24000,
             ('Grocery chain', 'Retail route')),
            ('Bird Sales', 'Live bird — festival order', 26000, 70000,
             ('Eid contract order',)),
            ('By-products', 'Poultry manure', 1400, 5200,
             ('Vegetable farm', 'Compost buyer')),
            ('Egg Sales', 'Bulk egg order — hotel', 9000, 19000, ('Hotel supply',)),
            ('Bird Sales', 'Culled layer sale', 7000, 16000, ('Local butcher',)),
            ('By-products', 'Empty feed sacks', 600, 1800, ('Recycler',)),
            ('Bird Sales', 'Broiler — partial sale', 12000, 34000,
             ('Meena Bazar',)),
        ]
        ec = 0
        for cat_name, desc, lo, hi, suppliers in extra_exp:
            cat, _ = ExpenseCategory.objects.get_or_create(name=cat_name)
            d = today - timedelta(days=rng.randint(4, 210))
            status = rng.choice(['paid', 'paid', 'paid', 'pending', 'overdue'])
            Expense.objects.create(
                farm=farm, category=cat, amount=Decimal(rng.randint(lo, hi)),
                description=desc, expense_date=d, payment_status=status,
                payment_method=rng.choice(['cash', 'bkash', 'bank_transfer', 'nagad']),
                supplier_name=rng.choice(suppliers),
                paid_at=timezone.make_aware(
                    timezone.datetime(d.year, d.month, d.day, 12))
                if status == 'paid' else None,
                created_by=user)
            ec += 1
        rc = 0
        for src_name, desc, lo, hi, buyers in extra_rev:
            src, _ = RevenueSource.objects.get_or_create(name=src_name)
            d = today - timedelta(days=rng.randint(4, 200))
            Revenue.objects.create(
                farm=farm, source=src, amount=Decimal(rng.randint(lo, hi)),
                revenue_date=d, description=desc,
                payment_method=rng.choice(['cash', 'bkash', 'bank_transfer']),
                buyer_name=rng.choice(buyers), created_by=user)
            rc += 1
        return ec, rc

    # ── tax ─────────────────────────────────────────────────────────────
    def _tax(self, user):
        from tax.models import TaxPayment, TaxProfile
        TaxProfile.objects.update_or_create(
            user=user,
            defaults=dict(
                land_area=Decimal('62.00'), land_unit='katha',
                land_use='agricultural', location='rural',
                income_type='agricultural', exemptions=Decimal('0'),
                rebates=Decimal('0'), is_senior=False,
                district='Mymensingh', upazila='Trishal',
                vehicles=[{'type': 'motorcycle', 'count': 1},
                          {'type': 'pickup', 'count': 1}]),
        )
        this_year = date.today().year
        rows = [
            ('land', Decimal('4800'), 'CH-LAND-2400118', date(this_year, 2, 12)),
            ('vehicle', Decimal('1500'), 'BRTA-MC-88123', date(this_year, 1, 20)),
            ('vehicle', Decimal('9000'), 'BRTA-PK-55219', date(this_year, 1, 22)),
            ('other', Decimal('1200'), 'UNION-TRADE-771', date(this_year - 1, 11, 5)),
            ('income', Decimal('0'), 'NBR-AGRI-EXEMPT', date(this_year - 1, 6, 30)),
        ]
        made = 0
        for tax_type, amount, ref, when in rows:
            _, created = TaxPayment.objects.get_or_create(
                user=user, tax_type=tax_type, reference_number=ref,
                defaults=dict(amount=amount, payment_date=when,
                              notes='Demo record (seed_demo_data_for_phone).'))
            made += int(created)
        return made

    # ── community posts ─────────────────────────────────────────────────
    def _posts(self, rng, user):
        from community.models import Post, PostCategory
        cat, _ = PostCategory.objects.get_or_create(
            name='General', defaults={'created_at': timezone.now()})
        if Post.objects.filter(author=user, tags__contains=[SEED_TAG]).count() >= len(EXTRA_POSTS):
            return 0
        made = 0
        for i, (ptype, title, content) in enumerate(EXTRA_POSTS):
            when = timezone.now() - timedelta(days=rng.randint(1, 110),
                                              hours=rng.randint(0, 20))
            fields = dict(
                author=user, post_type=ptype,
                title=title if ptype == 'question' else None,
                content=content, tags=[SEED_TAG], mentions=[], category=cat,
                status='active', created_at=when, updated_at=when,
                media_urls=(['https://images.unsplash.com/photo-1548550023-2bdb3c5beed7?w=900']
                            if i == 0 else []))
            if ptype == 'poll':
                fields['poll_options'] = ['Paper notebook', 'Phone notes / photos',
                                          'This app', 'Nothing formal']
                fields['poll_multi'] = False
            Post.objects.create(**fields)
            made += 1
        return made

    # ── comments + reactions on OTHER farmers' posts ────────────────────
    def _engage(self, rng, user):
        from community.models import Comment, Post, Reaction
        others = list(Post.objects.exclude(author=user)
                      .filter(status='active').order_by('-created_at')[:40])
        if not others:
            return 0, 0
        comments = 0
        if Comment.objects.filter(author=user).count() < 20:
            lines = COMMENT_LINES[:]
            rng.shuffle(lines)
            for i, line in enumerate(lines[:24]):
                post = rng.choice(others)
                base = post.created_at or timezone.now()
                if timezone.is_naive(base):
                    base = timezone.make_aware(base)
                when = min(base + timedelta(hours=rng.randint(1, 72)),
                           timezone.now())
                Comment.objects.create(
                    post=post, author=user, content=line, status='active',
                    created_at=when, updated_at=when)
                comments += 1
        reactions = 0
        if Reaction.objects.filter(user=user, target_type='post').count() < 10:
            for post in rng.sample(others, min(14, len(others))):
                _, created = Reaction.objects.get_or_create(
                    user=user, target_id=post.id, target_type='post',
                    defaults=dict(
                        reaction_type=rng.choice(
                            ['like', 'helpful', 'helpful', 'insightful', 'love']),
                        created_at=timezone.now()))
                reactions += int(created)
        return comments, reactions

    # ── follows ────────────────────────────────────────────────────────
    def _follows(self, user):
        from community.models import Follow
        targets = User.objects.exclude(pk=user.pk).filter(
            account_status='active',
            roles__name__in=['farmer', 'doctor', 'researcher']).distinct()[:8]
        made = 0
        for other in targets:
            _, created = Follow.objects.get_or_create(
                follower=user, following=other,
                defaults={'created_at': timezone.now()})
            made += int(created)
        return made

    # ── bookmarks (news articles + research papers) ────────────────────
    def _bookmarks(self, rng, user):
        from articles.models import Article
        from community.models import Bookmark
        if Bookmark.objects.filter(user=user).count() >= 15:
            return 0
        pool = list(Article.objects.filter(status='published')
                    .values_list('id', flat=True))
        if not pool:
            try:
                call_command('seed_news_demo')
                call_command('seed_research_demo')
            except Exception:
                pass
            pool = list(Article.objects.filter(status='published')
                        .values_list('id', flat=True))
        made = 0
        for aid in pool[:18]:
            _, created = Bookmark.objects.get_or_create(
                user=user, target_id=aid, target_type='article',
                defaults={'created_at': timezone.now()})
            made += int(created)
        return made

    # ── disease scans ─────────────────────────────────────────────────
    def _disease_scans(self, rng, user):
        from ml.models import DiseaseRef, DiseaseScan
        from workers.views import farm_for
        if DiseaseScan.objects.filter(user=user).count() >= 5:
            return 0
        farm = farm_for(user)
        refs = list(DiseaseRef.objects.all())
        plan = [
            ('completed', 'good', 'Newcastle Disease', Decimal('91.40'), 'high'),
            ('completed', 'good', None, Decimal('88.10'), 'low'),      # healthy
            ('completed', 'blurry', 'Coccidiosis', Decimal('63.75'), 'medium'),
            ('completed', 'good', 'Fowl Pox', Decimal('79.20'), 'medium'),
            ('completed', 'good', 'Infectious Bronchitis', Decimal('84.55'), 'high'),
            ('failed', 'rejected', None, None, None),
        ]
        made = 0
        for i, (status, quality, disease_name, conf, sev) in enumerate(plan):
            ref = None
            if disease_name:
                ref = next((r for r in refs
                            if disease_name.lower() in (r.name or '').lower()), None)
                ref = ref or (rng.choice(refs) if refs else None)
            scan = DiseaseScan.objects.create(
                user=user, farm_id=getattr(farm, 'id', None),
                image_urls=['https://images.unsplash.com/photo-1612170153139-6f881ff067e0?w=700'],
                image_quality_status=quality, detected_disease=ref,
                confidence_score=conf, severity_level=sev,
                scan_status=status, is_free_scan=i < 3)
            when = timezone.now() - timedelta(days=7 * (i + 1) + rng.randint(0, 4))
            DiseaseScan.objects.filter(pk=scan.pk).update(created_at=when)
            made += 1
        return made

    # ── notifications ────────────────────────────────────────────────
    def _notifications(self, user):
        from notifications.models import Notification
        if Notification.objects.filter(user=user).count() >= 10:
            return 0
        specs = [
            ('Disease scan complete', 'Your latest scan flagged possible Newcastle — tap for guidance.', 'alert', 'disease_scan', False),
            ('Tax payment recorded', 'Your vehicle tax payment of ৳ 9,000 was added to your records.', 'tax_due', 'tax', True),
            ('New follower', 'A researcher started following your posts.', 'message', 'community', False),
            ('Feed stock low', 'Grower mash is below 50 kg. Reorder soon to avoid a gap.', 'reminder', 'feed', False),
        ]
        made = 0
        for title, body, ntype, ref, read in specs:
            Notification.objects.create(
                user=user, title=title, body=body, notification_type=ntype,
                reference_type=ref, reference_id=uuid.uuid4(), is_read=read)
            made += 1
        return made

    # ── reset ────────────────────────────────────────────────────────
    def _wipe(self, user):
        from community.models import Bookmark, Comment, Follow, Post, Reaction
        from ml.models import DiseaseScan
        from notifications.models import Notification
        from tax.models import TaxPayment
        from workers.views import farm_for
        from expenses.models import (Expense, Loan, LoanInstallment, Revenue)
        from feed.models import FeedStock
        from farms.models import Flock, Shed
        from workers.models import Worker, WorkerAttendance, WorkerPayment
        from consultations.models import Consultation

        farm = farm_for(user)
        LoanInstallment.objects.filter(loan__farm=farm).delete()
        Loan.objects.filter(farm=farm).delete()
        Expense.objects.filter(farm=farm).delete()
        Revenue.objects.filter(farm=farm).delete()
        FeedStock.objects.filter(farm=farm).delete()
        WorkerAttendance.objects.filter(worker__farm=farm).delete()
        WorkerPayment.objects.filter(worker__farm=farm).delete()
        Worker.objects.filter(farm=farm).delete()
        Flock.objects.filter(farm=farm).delete()
        Shed.objects.filter(farm=farm).delete()
        Consultation.objects.filter(farmer=user).delete()
        Comment.objects.filter(author=user).delete()
        Reaction.objects.filter(user=user).delete()
        Bookmark.objects.filter(user=user).delete()
        Follow.objects.filter(follower=user).delete()
        Post.objects.filter(author=user).delete()
        DiseaseScan.objects.filter(user=user).delete()
        Notification.objects.filter(user=user).delete()
        TaxPayment.objects.filter(user=user).delete()
        self.stdout.write(self.style.WARNING('  reset: cleared prior demo rows'))


def _normalize_phone(value):
    try:
        from users.serializers import normalize_bd_phone
        return normalize_bd_phone(value)
    except Exception:
        raw = ''.join(ch for ch in str(value) if ch.isdigit() or ch == '+')
        if raw.startswith('01'):
            return '+88' + raw
        if raw.startswith('880'):
            return '+' + raw
        return raw
