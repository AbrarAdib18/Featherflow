"""Idempotent demo data for the farmer panel.

Populates every farmer-panel surface (farm profile, cost management, loans,
feed, labour, notifications, community, pharmacy orders, consultations) for the
three demo farmers created by ``seed_platform_demo`` so the UI can be exercised
end to end.

Run:  backend/venv/Scripts/python.exe manage.py seed_farmer_demo_data
      backend/venv/Scripts/python.exe manage.py seed_farmer_demo_data --reset

Safe to re-run: a farmer that already has seeded expenses is skipped unless
``--reset`` is passed, which wipes the seeded rows first.
"""
import random
import uuid
from datetime import date, time, timedelta
from decimal import Decimal

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from audit.models import AdminPanelRecord
from community.models import Post, PostCategory
from consultations.models import Consultation
from expenses.models import (Expense, ExpenseCategory, Loan, LoanInstallment,
                             Revenue, RevenueSource)
from farms.models import Flock, Shed
from feed.models import FeedStock, FeedType
from notifications.models import Notification
from profiles.models import DoctorProfile, FarmerProfile
from users.models import User
from workers.models import Worker, WorkerAttendance, WorkerPayment
from workers.views import farm_for

FARMERS = [
    {
        'email': 'farmer.rashed@example.com',
        'lat': Decimal('23.858600'), 'lng': Decimal('90.267300'),
        'location': 'Savar, Dhaka', 'birds': 4200, 'years': 8,
        'farm_type': 'broiler',
    },
    {
        'email': 'farmer.nasima@example.com',
        'lat': Decimal('24.747100'), 'lng': Decimal('90.420300'),
        'location': 'Mymensingh Sadar', 'birds': 2800, 'years': 6,
        'farm_type': 'layer',
    },
    {
        'email': 'farmer.sojib@example.com',
        'lat': Decimal('23.460700'), 'lng': Decimal('91.180700'),
        'location': 'Cumilla Sadar', 'birds': 1600, 'years': 4,
        'farm_type': 'mixed',
    },
]

EXPENSE_PLAN = [
    ('Feed', 8000, 20000, ('Nourish Feeds Ltd.', 'AgroFeed BD', 'Paragon Feed')),
    ('Feed', 6000, 16000, ('Nourish Feeds Ltd.', 'AgroFeed BD')),
    ('Medicines', 1500, 7000, ('GreenVet Pharmacy', 'AgroCare Veterinary Store')),
    ('Medicines', 900, 4500, ('PoultryMed Chattogram',)),
    ('Vaccines', 2000, 6000, ('GreenVet Pharmacy', 'Renata Animal Health')),
    ('Labor', 4000, 12000, ('Monthly wages',)),
    ('Utilities', 1200, 4000, ('DESCO', 'Palli Bidyut')),
    ('Chicks', 12000, 30000, ('Kazi Hatchery', 'CP Bangladesh')),
    ('Litter', 800, 2500, ('Local sawmill',)),
    ('Transport', 600, 3000, ('Pickup rental',)),
    ('Repairs', 1000, 5000, ('Shed maintenance',)),
    ('Utilities', 1000, 3500, ('Water pump diesel',)),
    ('Feed', 7000, 18000, ('AgroFeed BD',)),
    ('Medicines', 1200, 5000, ('AgroCare Veterinary Store',)),
]

REVENUE_PLAN = [
    ('Bird Sales', 18000, 55000, ('Karwan Bazar trader', 'Shwapno Procurement')),
    ('Bird Sales', 15000, 48000, ('Local wholesaler', 'Meena Bazar')),
    ('Egg Sales', 9000, 26000, ('Retail route', 'Grocery chain')),
    ('Egg Sales', 8000, 22000, ('Retail route',)),
    ('By-products', 1500, 6000, ('Manure buyer', 'Fish farm')),
    ('Bird Sales', 20000, 60000, ('Eid contract order',)),
    ('By-products', 1200, 4000, ('Compost buyer',)),
]

WORKER_PLAN = [
    ('Abul Kalam', 'Shed supervisor', 650),
    ('Rahima Begum', 'Feeder / cleaner', 480),
    ('Jashim Uddin', 'General labour', 500),
]

FEED_PLAN = [
    ('Starter Crumble', 'Nourish', 'kg'),
    ('Grower Mash', 'Paragon', 'kg'),
    ('Layer Pellet', 'AgroFeed', 'kg'),
]

POST_PLAN = [
    ('Broiler weight gain tips?', 'My 25-day broilers are averaging 1.3kg. Anyone using '
     'a different finisher feed that pushes this higher without hurting FCR?'),
    ('Newcastle vaccination schedule', 'Sharing the ND + IB schedule my vet set up after '
     'last winter’s outbreak. Day 7 Lasota, booster day 21, then every 8 weeks.'),
    ('Load-shedding is killing my brooding temps', 'Two hours without power this morning and '
     'the brooder dropped to 28°C. Looking for an affordable backup - IPS vs small generator?'),
    ('Good layer price in Mymensingh this week', 'Getting 11.5 tk/egg at the farm gate. '
     'Feed cost is up though so margins are thin. What are others seeing?'),
    ('Litter beetle problem', 'Darkling beetles everywhere after the last batch. What worked '
     'for you - a full clean-out and lime, or a specific insecticide?'),
    ('First time using the cost tracker here', 'Logged a full month of expenses and revenue. '
     'Eye opening how much feed actually is - 68% of my costs.'),
]

SEED_TAG = 'ff-demo-seed'


class Command(BaseCommand):
    help = 'Create idempotent demo data for the three demo farmer accounts.'

    def add_arguments(self, parser):
        parser.add_argument('--reset', action='store_true',
                            help='Delete previously seeded rows for these farmers first.')

    def handle(self, *args, **options):
        rng = random.Random(20260907)
        self._activate_doctors()
        self._provision_riders_and_pharmacies()
        doctors = list(DoctorProfile.objects.select_related('user').filter(
            user__account_status='active'))
        pharmacies = list(User.objects.filter(roles__name='pharmacy', account_status='active'))

        for spec in FARMERS:
            try:
                user = User.objects.get(email=spec['email'])
            except User.DoesNotExist:
                self.stdout.write(self.style.WARNING(
                    f"skip {spec['email']} - run seed_platform_demo first"))
                continue
            farm = farm_for(user)

            if options['reset']:
                self._wipe(user, farm)

            if Expense.objects.filter(farm=farm).exists():
                self.stdout.write(f"{spec['email']}: already seeded (use --reset to rebuild)")
                continue

            with transaction.atomic():
                counts = self._seed_farmer(rng, user, farm, spec, doctors, pharmacies)
            self.stdout.write(self.style.SUCCESS(
                f"{spec['email']}: " + ', '.join(f'{v} {k}' for k, v in counts.items())))

        self.stdout.write(self.style.SUCCESS('Farmer demo data ready.'))

    # ── doctors: make the seeded vets discoverable on the farmer vet map ──
    def _activate_doctors(self):
        # Anchor points near each demo farm (+ Dhaka) so every demo farmer sees
        # a handful of vets inside the 50 km "nearby" radius. Doctors without
        # saved coordinates are scattered ~3-20 km around a rotating anchor.
        rng = random.Random(4172026)
        anchors = [(float(f['lat']), float(f['lng'])) for f in FARMERS]
        anchors.append((23.8103, 90.4125))  # Dhaka
        updated = 0
        located = 0
        for i, prof in enumerate(DoctorProfile.objects.select_related('user')):
            u = prof.user
            if u.account_status != 'active':
                u.account_status = 'active'
                u.is_verified = True
                u.save(update_fields=['account_status', 'is_verified'])
            changed = []
            if not prof.is_verified:
                prof.is_verified = True
                changed.append('is_verified')
            if not prof.is_available:
                prof.is_available = True
                changed.append('is_available')
            if getattr(prof, 'availability_status', None) != 'available':
                prof.availability_status = 'available'
                changed.append('availability_status')
            if prof.latitude is None or prof.longitude is None:
                base_lat, base_lng = anchors[i % len(anchors)]
                # ~0.03-0.18 deg ≈ 3-20 km
                prof.latitude = Decimal(
                    str(round(base_lat + rng.uniform(-0.18, 0.18), 6)))
                prof.longitude = Decimal(
                    str(round(base_lng + rng.uniform(-0.18, 0.18), 6)))
                changed += ['latitude', 'longitude']
                located += 1
            if changed:
                prof.save(update_fields=changed)
            updated += 1
        if updated:
            self.stdout.write(
                f'activated {updated} doctor profile(s) for vet discovery'
                f' ({located} given demo coordinates)')

    # ── riders + pharmacy orgs: demo accounts need a profile row to use the
    #    delivery / pharmacy panels at all ────────────────────────────────
    def _provision_riders_and_pharmacies(self):
        from datetime import date as _date

        from profiles.models import DeliveryProfile, PharmacyOrganization

        riders = 0
        for u in User.objects.filter(roles__name='delivery'):
            if u.account_status != 'active':
                u.account_status = 'active'
                u.is_verified = True
                u.save(update_fields=['account_status', 'is_verified'])
            pd = u.profile_data if isinstance(u.profile_data, dict) else {}
            _, created = DeliveryProfile.objects.get_or_create(
                user=u,
                defaults=dict(
                    drivers_license_number=pd.get('license_number')
                    or f'RID-{uuid.uuid4().hex[:8].upper()}',
                    license_class='A',
                    license_expiry_date=_date(2030, 1, 1),
                    license_photo_url='admin-seed/license.jpg',
                    area_coverage=pd.get('service_area', 'Dhaka'),
                    prior_delivery_experience=pd.get('bio', ''),
                    is_online=False, current_status='offline',
                    rating=Decimal('4.7'), total_deliveries=0,
                ),
            )
            riders += 1 if created else 0

        orgs = 0
        for u in User.objects.filter(roles__name='pharmacy'):
            pd = u.profile_data if isinstance(u.profile_data, dict) else {}
            _, created = PharmacyOrganization.objects.get_or_create(
                user=u,
                defaults=dict(
                    business_name=pd.get('organization_name') or (u.full_name or 'Pharmacy'),
                    authorized_contact_person=pd.get('pharmacist_in_charge') or (u.full_name or 'Pharmacist'),
                    business_registration_number=pd.get('trade_license')
                    or f'TRAD-{uuid.uuid4().hex[:8].upper()}',
                    trade_license_url='admin-seed/trade-license.pdf',
                    tax_vat_tin_number=f'TIN-{uuid.uuid4().hex[:9].upper()}',
                    business_address=pd.get('bio') or 'Dhaka, Bangladesh',
                    responsible_pharmacist_name=pd.get('pharmacist_in_charge') or '',
                    is_verified=True,
                ),
            )
            orgs += 1 if created else 0

        if riders or orgs:
            self.stdout.write(
                f'provisioned {riders} delivery profile(s), {orgs} pharmacy org(s)')

    # ── wipe ──────────────────────────────────────────────────────────────
    def _wipe(self, user, farm):
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
        Notification.objects.filter(user=user).delete()
        Post.objects.filter(author=user).delete()
        AdminPanelRecord.objects.filter(
            module='pharmacy-orders', payload__farmer_id=str(user.id)).delete()

    # ── seed one farmer ───────────────────────────────────────────────────
    def _seed_farmer(self, rng, user, farm, spec, doctors, pharmacies):
        now = timezone.now()
        today = date.today()

        # profile ---------------------------------------------------------
        fp = FarmerProfile.objects.get(user=user)
        fp.farm_type = spec['farm_type']
        fp.number_of_birds = spec['birds']
        fp.years_in_farming = spec['years']
        fp.experience_level = 'expert' if spec['years'] >= 6 else 'intermediate'
        fp.farm_location = spec['location']
        fp.farm_address = f"{spec['location']}, Bangladesh"
        fp.feed_type = 'Commercial pellet + mash'
        fp.number_of_active_workers = len(WORKER_PLAN)
        fp.farm_photos = [
            'https://images.unsplash.com/photo-1548550023-2bdb3c5beed7?w=800',
            'https://images.unsplash.com/photo-1518492104633-130d0cc84637?w=800',
        ]
        if fp.created_at is None:
            fp.created_at = now
        fp.updated_at = now
        fp.save()

        farm.farm_name = fp.farm_name
        farm.farm_type = spec['farm_type']
        farm.location = spec['location']
        farm.address = fp.farm_address
        farm.latitude = spec['lat']
        farm.longitude = spec['lng']
        farm.total_sheds = 2
        farm.is_active = True
        if farm.created_at is None:
            farm.created_at = now
        farm.updated_at = now
        farm.save()

        # sheds + flocks -------------------------------------------------
        sheds = []
        for i in range(2):
            sheds.append(Shed.objects.create(
                farm=farm, shed_name=f'Shed {chr(65 + i)}',
                capacity=spec['birds'] // 2 + 400,
                current_bird_count=spec['birds'] // 2,
                shed_type='open-sided' if i == 0 else 'controlled',
                created_at=now, updated_at=now))
        flocks = []
        for i, shed in enumerate(sheds):
            start = today - timedelta(days=rng.randint(20, 120))
            qty = spec['birds'] // 2
            flocks.append(Flock.objects.create(
                farm=farm, shed=shed,
                batch_name=f'Batch {start.strftime("%b")}-{i + 1}',
                bird_type=spec['farm_type'] if spec['farm_type'] != 'mixed' else ('broiler' if i == 0 else 'layer'),
                breed='Cobb 500' if i == 0 else 'ISA Brown',
                quantity=qty, current_quantity=qty - rng.randint(20, 90),
                start_date=start, status='active',
                created_at=now, updated_at=now))

        # expenses ------------------------------------------------------
        exp_count = 0
        for name, lo, hi, suppliers in EXPENSE_PLAN:
            cat, _ = ExpenseCategory.objects.get_or_create(name=name)
            d = today - timedelta(days=rng.randint(5, 180))
            status = rng.choice(['paid', 'paid', 'paid', 'pending', 'overdue'])
            Expense.objects.create(
                farm=farm, category=cat,
                flock_id=rng.choice(flocks).id if rng.random() < 0.5 else None,
                amount=Decimal(rng.randint(lo, hi)),
                description=f'{name} purchase',
                expense_date=d, payment_status=status,
                payment_method=rng.choice(['cash', 'bkash', 'bank_transfer', 'nagad']),
                supplier_name=rng.choice(suppliers),
                paid_at=timezone.make_aware(
                    timezone.datetime(d.year, d.month, d.day, 12)) if status == 'paid' else None,
                created_by=user)
            exp_count += 1

        # revenue -----------------------------------------------------
        rev_count = 0
        for name, lo, hi, buyers in REVENUE_PLAN:
            src, _ = RevenueSource.objects.get_or_create(name=name)
            d = today - timedelta(days=rng.randint(5, 175))
            Revenue.objects.create(
                farm=farm, source=src,
                flock_id=rng.choice(flocks).id if rng.random() < 0.6 else None,
                amount=Decimal(rng.randint(lo, hi)),
                revenue_date=d, description=f'{name}',
                payment_method=rng.choice(['cash', 'bkash', 'bank_transfer']),
                buyer_name=rng.choice(buyers), created_by=user)
            rev_count += 1

        # loans -----------------------------------------------------
        loan_a = Loan.objects.create(
            farm=farm, lender_name='BRAC Bank Agri Loan',
            loan_amount=Decimal('150000'), interest_rate=Decimal('9.50'),
            start_date=today - timedelta(days=120), due_date=today + timedelta(days=245),
            remaining_balance=Decimal('96000'), status='active',
            purpose='Feed stock and shed expansion', term_months=12,
            requested_by=user, created_at=now, updated_at=now)
        for m in range(1, 5):
            due = today - timedelta(days=120) + timedelta(days=30 * m)
            LoanInstallment.objects.create(
                loan=loan_a, due_date=due, amount=Decimal('13500'),
                paid_date=due if due < today else None,
                status='paid' if due < today else 'pending')
        Loan.objects.create(
            farm=farm, lender_name='Local samity (cooperative)',
            loan_amount=Decimal('40000'), interest_rate=Decimal('12.00'),
            start_date=None, due_date=today + timedelta(days=90),
            remaining_balance=Decimal('40000'), status='pending',
            purpose='Working capital for next batch', term_months=6,
            requested_by=user, created_at=now, updated_at=now)

        # feed stock ----------------------------------------------
        feed_count = 0
        for fname, brand, unit in FEED_PLAN:
            ft, _ = FeedType.objects.get_or_create(
                name=fname, defaults={'brand': brand, 'unit': unit, 'created_at': now})
            FeedStock.objects.update_or_create(
                farm=farm, feed_type=ft,
                defaults=dict(
                    quantity_available=Decimal(rng.randint(20, 400)),
                    last_restocked_at=now - timedelta(days=rng.randint(2, 40)),
                    supplier_name=brand, cost_per_unit=Decimal(rng.randint(52, 74)),
                    created_at=now, updated_at=now))
            feed_count += 1

        # workers -----------------------------------------------
        for wname, role, wage in WORKER_PLAN:
            w = Worker.objects.create(
                farm=farm, full_name=wname, phone='+8801' + str(rng.randint(300000000, 999999999)),
                job_role=role, daily_wage=Decimal(wage),
                join_date=today - timedelta(days=rng.randint(60, 400)), status='active')
            for n in range(7):
                d = today - timedelta(days=n + 1)
                WorkerAttendance.objects.create(
                    worker=w, attendance_date=d,
                    status=rng.choice(['present', 'present', 'present', 'half_day', 'absent']),
                    check_in_time=time(7, 0), check_out_time=time(17, 0))
            WorkerPayment.objects.create(
                worker=w, amount=Decimal(wage) * 26, payment_date=today - timedelta(days=3),
                payment_method='cash', period_start=today - timedelta(days=33),
                period_end=today - timedelta(days=3), notes='Monthly wage')

        # notifications ----------------------------------------
        notif_specs = [
            ('Loan repayment due soon', 'Your BRAC Bank installment of ৳ 13,500 is due in 5 days.', 'loan_due', 'loan'),
            ('Expense marked overdue', 'A feed expense is past its due date. Tap to review and pay.', 'bill_due', 'expense'),
            ('Vet consultation confirmed', 'Your consultation has been accepted. Check the schedule.', 'reminder', 'consultation'),
            ('Prescription ready', 'A prescription from your vet is available to view.', 'message', 'prescription'),
            ('Pharmacy order update', 'Your medicine order is out for delivery.', 'alert', 'pharmacy_order'),
            ('Payout processed', 'Your cash-out request has been completed.', 'system', 'cashout'),
            ('Community reply', 'Someone replied to your post about broiler weight gain.', 'message', 'community'),
        ]
        for i, (title, body, ntype, ref) in enumerate(notif_specs):
            Notification.objects.create(
                user=user, title=title, body=body, notification_type=ntype,
                reference_type=ref, reference_id=uuid.uuid4(), is_read=i >= 4)

        # community posts -------------------------------------
        cat, _ = PostCategory.objects.get_or_create(
            name='General', defaults={'created_at': now})
        post_count = 0
        for title, content in rng.sample(POST_PLAN, 4):
            Post.objects.create(
                author=user, post_type='text', title=title, content=content,
                media_urls=[], tags=[SEED_TAG], mentions=[], category=cat,
                status='active',
                created_at=now - timedelta(days=rng.randint(1, 90)), updated_at=now)
            post_count += 1

        # pharmacy orders (best effort) ----------------------
        pharm_orders = self._seed_pharmacy_orders(rng, user, fp, pharmacies)

        # consultations (best effort) -----------------------
        consults = self._seed_consultations(rng, user, doctors)

        return {
            'sheds': 2, 'flocks': len(flocks), 'expenses': exp_count,
            'revenue': rev_count, 'loans': 2, 'feed': feed_count,
            'workers': len(WORKER_PLAN), 'notifications': len(notif_specs),
            'posts': post_count, 'pharmacy_orders': pharm_orders, 'consultations': consults,
        }

    # ── pharmacy orders ──────────────────────────────────────────────────
    def _seed_pharmacy_orders(self, rng, user, fp, pharmacies):
        from pharmacy.models import PharmacyMedicine
        from pharmacy.services import order_key
        made = 0
        statuses = ['pending', 'preparing', 'delivered']
        for pharmacy_user in pharmacies:
            meds = list(PharmacyMedicine.objects.filter(
                pharmacy_user=pharmacy_user, is_active=True, is_approved=True)[:3])
            if not meds:
                continue
            for status in statuses:
                order_id = f'ORD-{uuid.uuid4().hex[:10].upper()}'
                items = [{
                    'product_id': str(m.id), 'medicine_id': str(m.id),
                    'product_name': m.name, 'quantity': rng.randint(1, 4),
                    'unit_price': float(m.price), 'category': m.category,
                    'cold_chain_required': m.cold_chain_required,
                    'prescription_required': m.prescription_required,
                } for m in meds[:rng.randint(1, len(meds))]]
                subtotal = sum(i['unit_price'] * i['quantity'] for i in items)
                delivery_fee = 60.0
                created = timezone.now() - timedelta(days=rng.randint(2, 60))
                payload = {
                    'id': order_id, 'order_number': f'#PH-{order_id[-6:]}',
                    'owner_id': str(pharmacy_user.id), 'farmer_id': str(user.id),
                    'farmer_name': user.full_name or user.email,
                    'farmer_phone': user.phone or '',
                    'farm_name': (fp.farm_name or 'Poultry Farm'),
                    'delivery_address': fp.farm_address or user.present_address or 'Farm gate',
                    'delivery_method': 'delivery', 'payment_method': 'cod',
                    'payment_status': 'paid' if status == 'delivered' else 'pending',
                    'delivery_fee': delivery_fee, 'subtotal': round(subtotal, 2),
                    'total_amount': round(subtotal + delivery_fee, 2),
                    'prescription_image': None, 'requires_prescription_review': False,
                    'items': items, 'status': status,
                    'created_at': created.isoformat(),
                    'delivered_at': (created + timedelta(days=1)).isoformat() if status == 'delivered' else None,
                    'notes': '', 'seed': True,
                }
                AdminPanelRecord.objects.create(
                    module='pharmacy-orders',
                    record_id=order_key(pharmacy_user.id, order_id), payload=payload)
                made += 1
            break  # one pharmacy is enough for the demo
        return made

    # ── consultations ────────────────────────────────────────────────────
    def _seed_consultations(self, rng, user, doctors):
        if not doctors:
            return 0
        made = 0
        today = date.today()
        plan = [
            ('accepted', today + timedelta(days=rng.randint(2, 10)), 'online'),
            ('completed', today - timedelta(days=rng.randint(10, 40)), 'offline'),
            ('completed', today - timedelta(days=rng.randint(45, 90)), 'online'),
        ]
        for status, appt, mode in plan:
            prof = rng.choice(doctors)
            Consultation.objects.create(
                farmer=user, doctor=prof.user, mode=mode, status=status,
                urgency_level=rng.choice(['routine', 'routine', 'urgent']),
                appointment_date=appt, appointment_time=time(rng.randint(9, 16), 0),
                consultation_fee=getattr(prof, 'service_fee', None) or Decimal('800'),
                rating=rng.randint(4, 5) if status == 'completed' else None,
                review_text='Very helpful, clear guidance on treatment.' if status == 'completed' else '')
            made += 1
        return made
