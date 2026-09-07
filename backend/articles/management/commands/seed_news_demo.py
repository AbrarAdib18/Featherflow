"""Idempotent demo data for the farmer News / Research (Knowledge Portal) panel.

Seeds 12 realistic, published poultry articles across every content type the
portal shows (research papers, news, market reports, innovation, disease &
feed studies, and a Team FeatherFlow update).

Run:
    backend/venv/Scripts/python.exe manage.py seed_news_demo
    backend/venv/Scripts/python.exe manage.py seed_news_demo --reset

Safe to re-run: each article is matched by title and updated in place
(``update_or_create``), so running it twice creates no duplicates. ``--reset``
first deletes the articles this command previously seeded (matched by the
``ff-news-seed`` marker in ``content_details``).

To add more demo articles later: append an entry to ``ARTICLES`` below and
re-run the command — existing rows are left untouched, the new one is created.
"""
from datetime import date, timedelta

from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from articles.models import Article
from users.models import Role, User, UserRole

SEED_MARKER = 'ff-news-seed'
# Routed through the weserv.nl proxy so the image response carries CORS headers
# (Flutter web fetches images with XHR). Swap for a real CDN URL any time.
_PLACEHOLDER = 'https://images.weserv.nl/?url=picsum.photos/seed/{slug}/800/450&w=800&output=jpg'


def _para(*lines):
    return '\n\n'.join(lines)


# (title, content_type, category, source_type, keywords, is_featured,
#  days_ago, views, has_pdf, abstract, body)
ARTICLES = [
    (
        'New vaccine reduces Newcastle Disease mortality by 40%',
        'research_paper', 'Research', 'Research',
        ['newcastle', 'vaccine', 'mortality'], True, 2, 640, True,
        'A multi-farm field trial of a thermostable Newcastle Disease vaccine '
        'recorded a 40% drop in flock mortality versus the standard schedule.',
        _para(
            'Background: Newcastle Disease (ND) remains the single largest cause of '
            'catastrophic flock loss for smallholder poultry keepers in South Asia.',
            'Methods: 18 commercial broiler farms were randomised to either the '
            'conventional LaSota schedule or a thermostable I-2 strain delivered at '
            'day 4 and day 18. Mortality, weight gain and antibody titres were '
            'tracked over two production cycles.',
            'Results: Farms on the thermostable schedule saw mortality fall from a '
            'mean of 11.2% to 6.7% (a 40% relative reduction) with no difference in '
            'final body weight. Cold-chain failures did not affect the I-2 group.',
            'Takeaway: For farms with unreliable refrigeration, a thermostable ND '
            'vaccine is a low-cost way to protect against the disease that most '
            'often wipes out a flock.',
        ),
    ),
    (
        'Feed cost trends in Bangladesh - Q2 2026',
        'market_report', 'Market', 'Market',
        ['feed', 'prices', 'market'], False, 5, 410, True,
        'Commercial layer and broiler feed prices rose 6-9% through Q2 2026, '
        'driven by soybean meal import costs and a weaker taka.',
        _para(
            'Summary: Average finisher feed reached BDT 58/kg in June, up from BDT '
            '53/kg in March. Layer mash tracked similarly.',
            'Drivers: Soybean meal (up 12% CIF Chattogram), maize (up 4%), and a '
            '3.5% depreciation of the taka against the dollar.',
            'Regional picture: Mymensingh and Bogura mills held prices ~2% below the '
            'national average; Sylhet and Chattogram ran above it on transport cost.',
            'Outlook: Prices are expected to plateau in Q3 as the new maize harvest '
            'reaches mills. Farmers holding birds for Eid-ul-Adha should budget for '
            'the higher feed cost through the finishing period.',
        ),
    ),
    (
        'Best practices for litter management in broiler farms',
        'news', 'Best Practices', 'Team FeatherFlow',
        ['litter', 'biosecurity', 'management'], False, 8, 295, False,
        'Dry, friable litter is the cheapest disease-prevention tool on the farm. '
        'A practical routine for keeping moisture below 30%.',
        _para(
            'Why it matters: Wet, caked litter drives footpad dermatitis, ammonia '
            'burn and coccidiosis, and raises the whole-house pathogen load.',
            'Daily: Walk the house twice a day. Break up caked patches near drinkers '
            'and feed lines. Check that nipple drinkers are not leaking.',
            'Weekly: Top up with fresh dry material where depth has dropped below '
            '5 cm. Keep total depth at 8-10 cm.',
            'Between flocks: Full clean-out, disinfect, and rest the house for at '
            'least 10 days. Re-bed with sawdust or chopped rice straw at 30% '
            'moisture or lower.',
        ),
    ),
    (
        'How to spot early signs of Avian Influenza',
        'disease_study', 'Best Practices', 'Research',
        ['avian influenza', 'symptoms', 'reporting'], False, 11, 520, True,
        'The first 24 hours matter. A field guide to the early clinical signs of '
        'highly pathogenic avian influenza and what to do next.',
        _para(
            'Early signs: A sudden drop in feed and water intake, a fall in egg '
            'production, swollen wattles, purple discoloration of the comb, and '
            'unexplained deaths climbing day on day.',
            'What is NOT typical: Slow, scattered losses over weeks usually point to '
            'other causes - review Newcastle Disease and mycoplasma first.',
            'Immediate actions: Stop all bird and equipment movement on and off the '
            'farm. Restrict visitors. Bag and refrigerate any carcasses.',
            'Reporting: Contact your Upazila Livestock Officer the same day. Early '
            'reporting protects your compensation eligibility and your neighbours.',
        ),
    ),
    (
        'Government subsidy program for small poultry farmers',
        'news', 'Policy', 'News',
        ['subsidy', 'policy', 'finance'], False, 14, 780, False,
        'The Department of Livestock Services has opened applications for a '
        'BDT 500 crore support package targeting farms under 5,000 birds.',
        _para(
            'What is offered: A 4% interest subsidy on working-capital loans, a '
            'one-time feed voucher worth BDT 8,000, and free quarterly vet visits '
            'for registered farms.',
            'Who qualifies: Farms with a valid trade licence, fewer than 5,000 '
            'birds, and at least one completed production cycle.',
            'How to apply: Through your Upazila Livestock Office with your farm '
            'registration, national ID and last cycle sales records. The window '
            'closes at the end of the quarter.',
            'Note: Applications are processed in order of submission; incomplete '
            'files are returned rather than rejected.',
        ),
    ),
    (
        'Case study: Improving egg production with better lighting',
        'innovation', 'Best Practices', 'Innovation',
        ['layers', 'lighting', 'egg production'], False, 17, 340, False,
        'A Rajshahi layer farm lifted peak lay rate by 7 points after switching '
        'to a 16-hour warm-white LED programme with a gradual dawn/dusk ramp.',
        _para(
            'Starting point: The 8,000-bird flock was stuck at 82% lay at 32 weeks, '
            'with uneven shell quality.',
            'Change made: Replaced bare CFLs with 4-watt warm-white LEDs at 20 lux '
            'at bird height, on a 16L:8D schedule with a 30-minute simulated '
            'sunrise and sunset.',
            'Result over 8 weeks: Peak lay rose to 89%, cracked-egg rate fell from '
            '3.1% to 1.8%, and monthly electricity use dropped 22%.',
            'Cost: About BDT 34,000 in fittings, recovered in under four months on '
            'extra saleable eggs alone.',
        ),
    ),
    (
        'Research update: Alternative protein sources in poultry feed',
        'feed_study', 'Research', 'Research',
        ['feed formulation', 'protein', 'sustainability'], False, 21, 455, True,
        'Black soldier fly larvae meal can replace up to 20% of soybean meal in '
        'broiler diets with no loss of performance, a 16-week trial found.',
        _para(
            'Context: Soybean meal is the most expensive and most import-exposed '
            'ingredient in most Bangladeshi rations.',
            'Trial: 480 broilers on four diets replacing 0, 10, 20 and 30% of '
            'soybean meal with defatted black soldier fly larvae meal.',
            'Findings: The 10% and 20% groups matched the control on weight gain and '
            'feed conversion. The 30% group showed a small FCR penalty.',
            'Practical note: Larvae meal supply is still limited and priced close to '
            'soybean meal today, but the 20% substitution is a useful hedge when '
            'soy prices spike.',
        ),
    ),
    (
        'Market analysis: Egg price forecast for next 3 months',
        'market_report', 'Market', 'Market',
        ['eggs', 'price forecast', 'market'], False, 24, 610, True,
        'Farm-gate egg prices are projected to hold near BDT 11.5-12.0 per piece '
        'through the quarter, with a possible dip after the school holidays.',
        _para(
            'Current: Farm-gate prices sit at BDT 11.6/egg nationally, up from BDT '
            '10.9 a month ago on strong institutional demand.',
            'Supply: Placement data suggests layer numbers will rise ~4% next '
            'quarter as farms that culled during the price slump restock.',
            'Demand: Steady, with a seasonal softening likely mid-quarter during '
            'school holidays.',
            'Advice: Farms with storage should avoid over-committing to forward '
            'contracts below BDT 11/egg. Cash-flow-tight farms may prefer the '
            'certainty of a fixed price now.',
        ),
    ),
    (
        'Team FeatherFlow: New disease detection model launched',
        'team_update', 'Product', 'Team FeatherFlow',
        ['product', 'disease detection', 'ai'], True, 1, 210, False,
        'The in-app disease screening tool now runs an EfficientNet-b3 model '
        'covering 15 common poultry conditions from a single photo.',
        _para(
            'What changed: The Detect tab now analyses your photo on our servers '
            'and returns a ranked list of likely conditions with a confidence '
            'score, plus what to do and what to avoid.',
            'Coverage: 15 conditions including Newcastle Disease, coccidiosis, fowl '
            'pox, infectious bronchitis and healthy-bird detection.',
            'Important: The tool is a first-look aid, not a diagnosis. Low-confidence '
            'results are flagged as "Uncertain" - book a vet through the app for '
            'anything serious or spreading.',
            'Feedback: Use the report button on any result that looks wrong. Every '
            'report helps us retrain the model.',
        ),
    ),
    (
        'Biosecurity checklist for monsoon season',
        'news', 'Best Practices', 'Team FeatherFlow',
        ['biosecurity', 'monsoon', 'checklist'], False, 6, 380, False,
        'Standing water, damp bedding and more rodent movement make the monsoon '
        'the highest-risk period of the year. A 10-point checklist.',
        _para(
            'Perimeter: Clear drains and regrade low spots so water flows away from '
            'the house. Keep a 1-metre gravel or concrete apron rodent-free.',
            'Entry: One controlled entry point. Footbath with fresh disinfectant '
            'changed daily - rain dilutes it fast. Dedicated house boots.',
            'Inside: Check the roof and side curtains for leaks before every rain. '
            'Keep litter under 30% moisture; add fresh material after any wet spell.',
            'Feed and water: Store feed on pallets, off the floor, in sealed bins. '
            'Flush and sanitise water lines weekly.',
        ),
    ),
    (
        'Water quality and its hidden effect on broiler weight gain',
        'feed_study', 'Research', 'Research',
        ['water quality', 'broiler', 'performance'], False, 28, 265, True,
        'High total dissolved solids and bacterial contamination in drinking '
        'water cost up to 90g of final body weight per bird in a farm survey.',
        _para(
            'Survey: Water from 40 broiler farms was tested for TDS, hardness, '
            'nitrate, and total viable bacterial count, and matched to flock '
            'performance records.',
            'Findings: Farms above 1,500 ppm TDS or with detectable coliforms '
            'averaged 60-90g lower 35-day weight and a 4-6 point worse FCR.',
            'Cheap fixes: Weekly line flushing, end-of-flock line sanitation, and '
            'cleaning the header tank monthly closed most of the gap.',
            'When to test: Any new borehole, and once a year otherwise. A basic TDS '
            'meter costs under BDT 800.',
        ),
    ),
    (
        'Policy brief: New antibiotic use rules for commercial farms',
        'news', 'Policy', 'News',
        ['antibiotics', 'policy', 'compliance'], False, 30, 495, True,
        'From next quarter, growth-promoter antibiotics are banned in feed and '
        'all therapeutic use must be recorded against a vet prescription.',
        _para(
            'The rule: Antibiotic growth promoters may no longer be included in '
            'commercial feed. Therapeutic antibiotics require a written vet '
            'prescription kept on file for two years.',
            'Why: To slow antimicrobial resistance and protect export access for '
            'Bangladeshi poultry products.',
            'What to do now: Talk to your feed supplier about AGP-free formulations. '
            'Start a simple treatment logbook: date, house, product, dose, '
            'withdrawal period, prescribing vet.',
            'Support: Registered farms can request a free compliance visit through '
            'the Department of Livestock Services.',
        ),
    ),
]


class Command(BaseCommand):
    help = 'Idempotently seed 12 published demo articles for the farmer news / research panel.'

    def add_arguments(self, parser):
        parser.add_argument('--reset', action='store_true',
                            help='Delete previously seeded demo articles first.')

    @transaction.atomic
    def handle(self, *args, **options):
        now = timezone.now()

        role, _ = Role.objects.get_or_create(
            name='researcher', defaults={'panel_type': 'researcher'})
        author, created = User.objects.get_or_create(
            email='news.desk@featherflow.example',
            defaults=dict(
                phone='+8801700009100', full_name='FeatherFlow Editorial Desk',
                present_address='Dhaka, Bangladesh', date_of_birth=date(1990, 1, 1),
                consent_terms=True, account_status='active', is_verified=True,
                created_at=now, updated_at=now,
            ),
        )
        if created:
            author.set_password('FeatherflowDemo@2026')
            author.save()
        UserRole.objects.get_or_create(user=author, role=role)

        if options['reset']:
            deleted, _ = Article.objects.filter(
                content_details__seed_marker=SEED_MARKER).delete()
            self.stdout.write(f'  reset: deleted {deleted} previously seeded row(s)')

        made = updated = 0
        for (title, content_type, category, source_type, keywords, featured,
             days_ago, views, has_pdf, abstract, body) in ARTICLES:
            slug = title.lower().replace(' ', '-').replace(':', '').replace(',', '')[:60]
            published = now - timedelta(days=days_ago)
            defaults = dict(
                author=author,
                abstract=abstract,
                body=body,
                category=category,
                keywords=keywords,
                references_list=[],
                pdf_url=(f'https://featherflow.example/library/{slug}.pdf' if has_pdf else None),
                farmer_summary=abstract,
                status='published',
                version=1,
                read_count=views,
                co_authors=[],
                content_details={
                    'seed_marker': SEED_MARKER,
                    'source_type': source_type,
                    'image_url': _PLACEHOLDER.format(slug=slug),
                },
                review_notes='',
                is_featured=featured,
                published_at=published,
                updated_at=now,
            )
            obj, was_created = Article.objects.get_or_create(
                title=title, content_type=content_type,
                defaults={**defaults, 'created_at': published},
            )
            if was_created:
                made += 1
            else:
                for field, value in defaults.items():
                    setattr(obj, field, value)
                obj.save()
                updated += 1

        total = Article.objects.filter(status='published').count()
        self.stdout.write(self.style.SUCCESS(
            f'News demo ready: {made} created, {updated} updated, '
            f'{len(ARTICLES)} demo articles total ({total} published articles in all).'))
