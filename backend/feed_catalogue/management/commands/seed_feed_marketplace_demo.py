"""Feed marketplace UX-correction demo data (supersedes/expands the older
``seed_feed_demo_data`` — kept as a thin backward-compatible alias that
calls into this command, see that file).

Run:  python manage.py seed_feed_marketplace_demo [--reset]

Idempotent (update_or_create / get_or_create throughout, deterministic
record ids for orders); safe to rerun. ``--reset`` only ever deletes rows
this command itself owns (companies named "Demo …", their products, and
AdminPanelRecord rows with a FEEDMKT- id) — it never touches unrelated
farmer/pharmacy/doctor/admin data.

Seeds: 1 feed admin, 4 feed companies (with generated logo/cover images,
one left 'pending'), 25 products (20 approved + 3 pending_review + 1
rejected + 1 suspended, each with a generated primary image) across every
category the UX spec calls for, 3 farmer flocks reused from
seed_farmer_demo_data if present, 2 delivery riders, and 6 feed orders
spanning created/confirmed/preparing/out_for_delivery/delivered/cancelled.
"""
from datetime import date, timedelta
from decimal import Decimal

from django.core.management import call_command
from django.core.management.base import BaseCommand
from django.utils import timezone

from audit.models import AdminPanelRecord
from farms.models import Farm, Flock
from feed.models import FeedConsumption, FeedingGuideline, FeedType
from feed_catalogue.models import FeedCompany, FeedProduct
from feed_catalogue.uploads import generate_placeholder_image
from notifications.models import Notification
from profiles.models import DeliveryProfile, FarmerProfile
from users.models import Role, User

PASSWORD = 'FeatherflowDemo@2026'
RECORD_PREFIX = 'FEEDMKT-'


def _user(email, phone, name, address, role_name, status='active', verified=True):
    role, _ = Role.objects.get_or_create(
        name=role_name, defaults={'panel_type': 'admin' if role_name == 'feed_admin' else role_name})
    user = User.objects.filter(email=email).first()
    if user is None:
        user = User.objects.create_user(
            email=email, password=PASSWORD, phone=phone, full_name=name,
            date_of_birth=date(1990, 1, 1), present_address=address, consent_terms=True,
            account_status=status, is_verified=verified)
    user.roles.add(role)
    return user


class Command(BaseCommand):
    help = 'Seed demo data (with real generated images) for the feed marketplace + Feed Admin panel.'

    def add_arguments(self, parser):
        parser.add_argument('--reset', action='store_true',
                            help='Delete previously-seeded feed-marketplace-demo rows first, then reseed.')

    def handle(self, *args, **options):
        counts = {'created': 0, 'updated': 0, 'skipped': 0}
        if options['reset']:
            self._reset()
        if not FeedingGuideline.objects.exists():
            call_command('seed_feeding_guidelines')

        feed_admin = _user('feedadmin.demo@example.com', '+8801711000801', 'Feed Admin Demo',
                          'Tejgaon, Dhaka', 'feed_admin')
        self.stdout.write(self.style.SUCCESS(f'Feed admin: {feed_admin.email}'))

        companies = self._seed_companies(feed_admin, counts)
        products = self._seed_products(companies, feed_admin, counts)
        farmers = self._seed_farmers_and_flocks(counts)
        riders = self._seed_riders(feed_admin, counts)
        self._seed_orders(farmers, products, riders, feed_admin, counts)

        self.stdout.write(self.style.SUCCESS(
            f'Done. created={counts["created"]} updated={counts["updated"]} skipped={counts["skipped"]} '
            f'— {len(companies)} companies, {len(products)} products, {len(farmers)} farmer flocks, '
            f'{len(riders)} riders.'))

    def _reset(self):
        companies = FeedCompany.objects.filter(name__startswith='Demo ')
        FeedProduct.objects.filter(company__in=companies).delete()
        companies.delete()
        AdminPanelRecord.objects.filter(module='feed-orders', record_id__startswith=f'feed:{RECORD_PREFIX}').delete()
        # Also clean up the older command's ids so re-running either command
        # after a --reset never leaves stale duplicates behind.
        AdminPanelRecord.objects.filter(module='feed-orders', record_id__startswith='feed:FEEDDEMO-').delete()
        self.stdout.write('Reset previous feed marketplace demo data.')

    def _seed_companies(self, feed_admin, counts):
        specs = [
            ('Demo Nourish Feeds Ltd', 'Kamal Hossain', '+8801700000701', 'nourishfeeds@example.com',
             'Savar, Dhaka', 'Dhaka', 'Savar', 'active',
             'A leading poultry feed manufacturer supplying broiler and layer feed across Dhaka division.'),
            ('Demo Golden Grain Feeds', 'Nasrin Akter', '+8801700000702', 'goldengrain@example.com',
             'Gazipur', 'Gazipur', 'Gazipur Sadar', 'active',
             'Family-owned feed mill specialising in breeder and chick starter formulas.'),
            ('Demo Premium Poultry Nutrition', 'Rafiqul Islam', '+8801700000703', 'premiumpoultry@example.com',
             'Narayanganj', 'Narayanganj', 'Narayanganj Sadar', 'active',
             'Premium nutrition brand offering vitamin/mineral supplements alongside standard feed lines.'),
            ('Demo BioFeed Solutions', 'Farida Yasmin', '+8801700000704', 'biofeed@example.com',
             'Mymensingh', 'Mymensingh', 'Mymensingh Sadar', 'pending',
             'New applicant — awaiting Feed Admin review before going active.'),
        ]
        companies = []
        for name, contact, phone, email, address, district, upazila, status, description in specs:
            now = timezone.now()
            existing = FeedCompany.objects.filter(name=name).first()
            company, created = FeedCompany.objects.update_or_create(
                name=name, defaults={
                    'contact_person': contact, 'contact_phone': phone, 'contact_email': email,
                    'address': address, 'district': district, 'upazila': upazila,
                    'description': description, 'status': status,
                    'created_by': feed_admin, 'created_at': now, 'updated_at': now,
                })
            if not company.logo_url:
                company.logo_url = generate_placeholder_image(name.replace('Demo ', ''), color=(27, 94, 32), size=(300, 300))
            if not company.cover_url:
                company.cover_url = generate_placeholder_image(f'{name.replace("Demo ", "")} — Cover', color=(56, 142, 60), size=(900, 300))
            company.save(update_fields=['logo_url', 'cover_url'])
            counts['created' if created else ('skipped' if existing else 'updated')] += 1
            companies.append(company)
        return companies

    def _seed_products(self, companies, feed_admin, counts):
        # (name, feed_stage, bird_type, unit, price, stock, min_qty)
        approved_specs = [
            ('Starter Crumble Premium', 'starter', 'broiler', 'bag_25kg', 1450, 200, 1),
            ('Broiler Starter Economy', 'starter', 'broiler', 'bag_25kg', 1320, 150, 1),
            ('Broiler Grower Pellet', 'grower', 'broiler', 'bag_25kg', 1380, 180, 1),
            ('Broiler Grower Economy', 'grower', 'broiler', 'bag_25kg', 1290, 160, 1),
            ('Broiler Finisher Pellet', 'finisher', 'broiler', 'bag_50kg', 2600, 150, 1),
            ('Broiler Finisher Premium', 'finisher', 'broiler', 'bag_50kg', 2750, 90, 1),
            ('Layer Starter Mash', 'starter', 'layer', 'bag_25kg', 1400, 120, 1),
            ('Layer Starter Economy', 'starter', 'layer', 'bag_25kg', 1310, 100, 1),
            ('Layer Grower Mash', 'grower', 'layer', 'bag_25kg', 1420, 100, 1),
            ('Layer Mash Premium', 'layer', 'layer', 'bag_50kg', 2750, 200, 1),
            ('Layer Feed Economy', 'layer', 'layer', 'bag_50kg', 2500, 140, 1),
            ('Chick Starter Crumble', 'starter', 'chick', 'bag_25kg', 1500, 90, 1),
            ('Chick Grower Feed', 'grower', 'chick', 'bag_25kg', 1450, 70, 1),
            ('Breeder Rearing Feed', 'grower', 'breeder', 'bag_25kg', 1600, 60, 1),
            ('Breeder Layer Feed', 'layer', 'breeder', 'bag_50kg', 2900, 80, 1),
            ('Vitamin & Mineral Supplement', 'supplement', 'other', 'kg', 320, 500, 5),
            ('Electrolyte & Vitamin Booster', 'supplement', 'other', 'kg', 280, 300, 5),
            ('Calcium Shell Grit', 'supplement', 'layer', 'kg', 150, 400, 5),
            ('Multivitamin Powder', 'supplement', 'other', 'kg', 350, 250, 5),
            ('Amino Acid Growth Booster', 'supplement', 'broiler', 'kg', 410, 200, 5),
        ]
        pending_specs = [
            ('New Formula Starter Mix', 'starter', 'broiler', 'bag_25kg', 1470, 50, 1),
            ('Organic Layer Blend', 'layer', 'layer', 'bag_25kg', 1600, 40, 1),
            ('Herbal Growth Supplement', 'supplement', 'other', 'kg', 400, 100, 5),
        ]
        # (name, stage, bird, unit, price, stock, min_qty, final_status, rejection_reason)
        other_specs = [
            ('Recalled Broiler Mix (test)', 'starter', 'broiler', 'bag_25kg', 1200, 0, 1,
             'rejected', 'Failed nutritional content verification — resubmit with lab results.'),
            ('Discontinued Layer Formula', 'layer', 'layer', 'bag_50kg', 2600, 30, 1,
             'suspended', None),
        ]
        products = []

        def _save_product(pname, ftype, btype, unit, price, stock, min_qty, company, status,
                          approved_by=None, rejection_reason=None):
            now = timezone.now()
            existing = FeedProduct.objects.filter(company=company, product_name=pname).first()
            product, created = FeedProduct.objects.update_or_create(
                company=company, product_name=pname, defaults={
                    'brand': company.name.replace('Demo ', ''), 'feed_type': ftype, 'bird_type': btype,
                    'unit': unit, 'price': Decimal(str(price)), 'stock_quantity': stock,
                    'min_order_quantity': min_qty, 'approval_status': status, 'approved_by': approved_by,
                    'rejection_reason': rejection_reason,
                    'description': f'{pname} — demo catalogue item for {btype} {ftype} stage.',
                    'ingredients': 'Maize, soybean meal, rice bran, vitamins & minerals premix.',
                    'nutritional_info': {'protein_percent': 20.0, 'energy_kcal_per_kg': 2900},
                    'created_by': feed_admin, 'created_at': now, 'updated_at': now,
                })
            if not product.image_url:
                product.image_url = generate_placeholder_image(pname, color=(56, 142, 60))
                product.save(update_fields=['image_url'])
            counts['created' if created else ('skipped' if existing else 'updated')] += 1
            return product

        for i, (pname, ftype, btype, unit, price, stock, min_qty) in enumerate(approved_specs):
            company = companies[i % len(companies)]
            products.append(_save_product(pname, ftype, btype, unit, price, stock, min_qty,
                                          company, 'approved', approved_by=feed_admin))
        for i, (pname, ftype, btype, unit, price, stock, min_qty) in enumerate(pending_specs):
            company = companies[i % len(companies)]
            _save_product(pname, ftype, btype, unit, price, stock, min_qty, company, 'pending_review')
        for pname, ftype, btype, unit, price, stock, min_qty, status, reason in other_specs:
            company = companies[0]
            _save_product(pname, ftype, btype, unit, price, stock, min_qty, company, status,
                         approved_by=feed_admin if status == 'suspended' else None, rejection_reason=reason)
        return products

    def _seed_farmers_and_flocks(self, counts):
        specs = [
            ('farmer.rashed@example.com', '+8801700000101', 'Rashed Karim', 'Savar, Dhaka',
             'Demo Broiler Batch', 'broiler', 'Cobb 500', 1000, 5),
            ('farmer.nasima@example.com', '+8801700000102', 'Nasima Begum', 'Gazipur',
             'Demo Layer Flock', 'layer', 'Lohmann Brown', 500, 60),
            ('farmer.sojib@example.com', '+8801700000103', 'Sojib Hasan', 'Narayanganj',
             'Demo Chick Batch', 'chick', 'Sonali', 300, 10),
        ]
        farmers = []
        feed_type, _ = FeedType.objects.get_or_create(name='Demo Broiler Starter', defaults={'unit': 'kg'})
        for email, phone, name, address, batch, bird_type, breed, qty, age_days in specs:
            user = _user(email, phone, name, address, 'farmer')
            profile, _created = FarmerProfile.objects.get_or_create(
                user=user, defaults={
                    'farm_name': f'{name} Farm', 'owner_name': name, 'farm_location': address,
                    'farm_address': address, 'farm_type': bird_type, 'number_of_birds': qty,
                })
            farm = Farm.objects.filter(farmer=profile).order_by('created_at').first()
            if farm is None:
                farm = Farm.objects.create(
                    farmer=profile, farm_name=profile.farm_name, farm_type=bird_type,
                    location=address, address=address)
            start = date.today() - timedelta(days=age_days)
            flock, created = Flock.objects.update_or_create(
                farm=farm, batch_name=batch, defaults={
                    'bird_type': bird_type, 'breed': breed, 'quantity': qty,
                    'current_quantity': qty, 'start_date': start, 'status': 'active',
                })
            counts['created' if created else 'skipped'] += 1
            for days_ago in (10, 5, 2):
                FeedConsumption.objects.get_or_create(
                    flock=flock, feed_type=feed_type, consumed_date=date.today() - timedelta(days=days_ago),
                    defaults={'quantity_consumed': Decimal('25.5'), 'recorded_by': user, 'notes': 'Demo seed'})
            Notification.objects.get_or_create(
                user=user, title='Today\'s feeding guidance',
                body=f'{batch}: demo seeded feeding reminder.', reference_type='feed_daily_reminder',
                reference_id=flock.id, defaults={'notification_type': 'reminder'})
            farmers.append({'user': user, 'farm': farm, 'flock': flock})
        return farmers

    def _seed_riders(self, feed_admin, counts):
        specs = [
            ('rider.arif@example.com', '+8801711000401', 'Arif Mahmud', 'Mirpur, Dhaka', True),
            ('rider.feeddemo2@example.com', '+8801711000802', 'Karim Uddin', 'Uttara, Dhaka', True),
        ]
        riders = []
        for email, phone, name, address, approved in specs:
            user = _user(email, phone, name, address, 'delivery')
            profile, created = DeliveryProfile.objects.get_or_create(
                user=user, defaults={
                    'drivers_license_number': f'DL-FEEDDEMO-{user.id.hex[:6]}', 'license_class': 'B',
                    'license_expiry_date': date(2031, 6, 30), 'license_photo_url': 'demo-seed/license.jpg',
                    'area_coverage': address, 'current_status': 'offline',
                    'approved_by_admin': feed_admin if approved else None,
                })
            counts['created' if created else 'skipped'] += 1
            if approved and profile.approved_by_admin_id is None:
                profile.approved_by_admin = feed_admin
                profile.save(update_fields=['approved_by_admin', 'updated_at'])
            riders.append(profile)
        return riders

    def _seed_orders(self, farmers, products, riders, feed_admin, counts):
        if not farmers or not products:
            return
        approved_products = [p for p in products if p.approval_status == 'approved']
        rider = riders[0] if riders else None
        # (status, assign_rider, delivery_status_if_assigned)
        specs = [
            ('created', False, None),
            ('confirmed', False, None),
            ('preparing', False, None),
            ('out_for_delivery', True, 'on_the_way'),
            ('delivered', True, 'delivered'),
            ('cancelled', False, None),
        ]
        for i, (order_status, assign, d_status) in enumerate(specs):
            farmer_entry = farmers[i % len(farmers)]
            product = approved_products[i % len(approved_products)]
            order_id = f'{RECORD_PREFIX}{i+1:03d}'
            record_id = f'feed:{order_id}'
            if AdminPanelRecord.objects.filter(module='feed-orders', record_id=record_id).exists():
                counts['skipped'] += 1
                continue
            qty = 2
            unit_price = float(product.price)
            payload = {
                'id': order_id, 'order_number': f'#FM-DEMO{i+1}',
                'farmer_id': str(farmer_entry['user'].id),
                'farmer_name': farmer_entry['user'].full_name,
                'farmer_phone': farmer_entry['user'].phone,
                'delivery_address': farmer_entry['user'].present_address,
                'latitude': 23.81 + i * 0.01, 'longitude': 90.41 + i * 0.01,
                'location_label': '', 'contact_phone': farmer_entry['user'].phone,
                'payment_method': 'cod', 'payment_status': 'paid' if order_status == 'delivered' else 'pending',
                'payment_mode': 'cod', 'delivery_fee': 60.0,
                'subtotal': round(unit_price * qty, 2), 'total_amount': round(unit_price * qty + 60.0, 2),
                'items': [{
                    'product_id': str(product.id), 'product_name': product.product_name,
                    'company_name': product.company.name, 'quantity': qty, 'unit_price': unit_price,
                    'unit': product.unit, 'line_total': round(unit_price * qty, 2),
                }],
                'status': order_status, 'delivery_notes': 'Demo seeded order.',
                'created_at': timezone.now().isoformat(), 'delivered_at': None,
                'delivery_order_id': None, 'assigned_rider_id': None,
            }
            if order_status == 'cancelled':
                payload['cancel_reason'] = 'Demo seed — cancelled example.'
            AdminPanelRecord.objects.create(module='feed-orders', record_id=record_id, payload=payload)
            counts['created'] += 1
            if assign and rider is not None:
                from delivery.models import DeliveryOrder
                order = DeliveryOrder.objects.create(
                    delivery_person=rider, order_reference_id=AdminPanelRecord.objects.get(
                        module='feed-orders', record_id=record_id).id,
                    order_type='marketplace', pickup_address='Feed warehouse',
                    delivery_address=payload['delivery_address'],
                    delivery_lat=payload['latitude'], delivery_lng=payload['longitude'],
                    status=d_status, is_pharmacy_delivery=False,
                    notes=f'Demo seed — {payload["order_number"]}',
                    assigned_at=timezone.now(),
                    delivered_at=timezone.now() if d_status == 'delivered' else None,
                    created_at=timezone.now())
                rec = AdminPanelRecord.objects.get(module='feed-orders', record_id=record_id)
                rec.payload = {**rec.payload, 'delivery_order_id': str(order.id), 'assigned_rider_id': str(rider.id)}
                rec.save(update_fields=['payload', 'updated_at'])
