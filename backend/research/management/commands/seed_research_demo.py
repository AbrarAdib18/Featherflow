import uuid
from datetime import date, timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from articles.models import Article
from community.models import Bookmark, Report
from profiles.models import ResearcherProfile
from research.models import ArticleVersionSnapshot, ProfileChangeApplication, ResearchTag
from subscriptions.models import Subscription, SubscriptionPlan
from users.models import Role, User, UserRole

PASSWORD = 'FeatherflowDemo@2026'


class Command(BaseCommand):
    help = ('Idempotently seeds realistic Researchers Panel demo data: researchers '
            'in every verification state, papers/disease-updates/innovations across '
            'every review status, a team update, tags, bookmarks, a profile change '
            'application, and a content report. Safe to re-run.')

    def handle(self, *args, **options):
        now = timezone.now()

        def make_user(email, phone, name, role_name, *, account_status='active', is_verified=True):
            role, _ = Role.objects.get_or_create(
                name=role_name,
                defaults={'panel_type': 'admin' if role_name.startswith('admin_') else role_name},
            )
            user, _ = User.objects.update_or_create(
                email=email,
                defaults={
                    'phone': phone, 'full_name': name, 'present_address': 'Dhaka, Bangladesh',
                    'date_of_birth': date(1990, 1, 1), 'preferred_language': 'en',
                    'consent_terms': True, 'consent_background_check': True,
                    'account_status': account_status, 'is_verified': is_verified,
                    'created_at': now, 'updated_at': now,
                },
            )
            user.set_password(PASSWORD)
            user.save()
            UserRole.objects.get_or_create(user=user, role=role)
            return user

        # ── Researchers in every verification state ──────────────────────
        fariha = make_user('research.fariha@example.com', '+8801700001401', 'Fariha Tasnim', 'researcher')
        mahmud = make_user('research.mahmud@example.com', '+8801700001402', 'Mahmudul Hasan', 'researcher')
        sabiha = make_user('research.sabiha@example.com', '+8801700001403', 'Sabiha Noor', 'researcher')

        fariha_profile, _ = ResearcherProfile.objects.update_or_create(
            user=fariha, defaults=dict(
                institution_name='Bangladesh Agricultural University',
                institutional_email='fariha.tasnim@bau.edu.bd', department='Poultry Science',
                highest_degree='PhD', field_of_study='Avian Epidemiology',
                university_name='Bangladesh Agricultural University', graduation_year=2019,
                cv_url='https://example.com/cv/fariha-tasnim.pdf',
                publications_portfolio_url='https://scholar.example.com/fariha-tasnim',
                areas_of_expertise=['Avian epidemiology', 'Disease surveillance', 'Biosecurity'],
                years_of_research_experience=7,
                poultry_specific_experience='Seven years studying disease surveillance systems on commercial broiler and layer farms.',
                research_role_type='disease',
                ethics_certificate_url='https://example.com/certs/fariha-ethics.pdf',
                conflict_of_interest_declaration=True, publication_consent=True, ip_agreement=True,
                reference_name='Prof. Kamal Uddin', reference_title='Dean, Faculty of Veterinary Science',
                reference_email='kamal.uddin@bau.edu.bd',
                is_verified=True, approved_by_admin=None, created_at=now, updated_at=now,
            ))
        mahmud_profile, _ = ResearcherProfile.objects.update_or_create(
            user=mahmud, defaults=dict(
                institution_name='Bangladesh Agricultural University',
                institutional_email='mahmudul.hasan@bau.edu.bd', department='Animal Nutrition',
                highest_degree='PhD', field_of_study='Poultry Nutrition',
                university_name='Bangladesh Agricultural University', graduation_year=2016,
                cv_url='https://example.com/cv/mahmudul-hasan.pdf',
                publications_portfolio_url='https://scholar.example.com/mahmudul-hasan',
                areas_of_expertise=['Feed formulation', 'Automation', 'Sustainability'],
                years_of_research_experience=10,
                poultry_specific_experience='Ten years developing low-cost feed formulations and farm automation for smallholders.',
                research_role_type='nutrition',
                ethics_certificate_url='https://example.com/certs/mahmud-ethics.pdf',
                conflict_of_interest_declaration=True, publication_consent=True, ip_agreement=True,
                reference_name='Dr. Ayesha Siddika', reference_title='Head of Department, Animal Nutrition',
                reference_email='ayesha.siddika@bau.edu.bd',
                is_verified=True, created_at=now, updated_at=now,
            ))
        sabiha_profile, _ = ResearcherProfile.objects.update_or_create(
            user=sabiha, defaults=dict(
                institution_name='Bangladesh Livestock Research Institute',
                institutional_email='sabiha.noor@blri.gov.bd', department='Vaccine Research',
                highest_degree='MSc', field_of_study='Veterinary Immunology',
                university_name='Chattogram Veterinary and Animal Sciences University', graduation_year=2022,
                cv_url='https://example.com/cv/sabiha-noor.pdf',
                areas_of_expertise=['Vaccine evaluation', 'Flock immunity'],
                years_of_research_experience=2,
                poultry_specific_experience='Early-career scientific officer researching vaccine response in layer flocks.',
                research_role_type='disease',
                conflict_of_interest_declaration=True, publication_consent=True, ip_agreement=True,
                is_verified=False, created_at=now, updated_at=now,
            ))

        # ── Admin account for testing moderation screens ──────────────────
        research_admin = make_user(
            'admin.research@example.com', '+8801700001900', 'Research & Content Admin',
            'admin_research')

        # ── A farmer account to bookmark/report content from the portal ──
        farmer = make_user(
            'farmer.rashed@example.com', '+8801700001101', 'Md. Rashed Karim', 'farmer')

        # ── Premium subscriptions for the two verified researchers ────────
        plan = SubscriptionPlan.objects.filter(
            is_active=True, features_unlocked__contains=['researcher_panel']).order_by('price').first()
        if plan:
            for user in (fariha, mahmud):
                Subscription.objects.get_or_create(
                    user=user, plan=plan, status='active',
                    defaults={'id': uuid.uuid4(), 'started_at': now, 'expires_at': now + timedelta(days=365),
                              'created_at': now},
                )

        # ── Tags ───────────────────────────────────────────────────────────
        def tag(slug):
            return ResearchTag.objects.filter(slug=slug).first()

        newcastle = tag('newcastle-disease')
        broiler = tag('broiler')
        vaccination = tag('vaccination')
        feed = tag('feed-formulation')
        automation = tag('automation')
        layer = tag('layer')

        def make_article(*, author, content_type, title, abstract, body, category,
                          keywords, farmer_summary, status, co_authors=None,
                          content_details=None, tags=None, is_featured=False,
                          review_notes='', views=0, published=False):
            article, _ = Article.objects.update_or_create(
                author=author, title=title, content_type=content_type,
                defaults=dict(
                    abstract=abstract, body=body, category=category, keywords=keywords or [],
                    references_list=[], pdf_url=None, farmer_summary=farmer_summary,
                    status=status, version=1, read_count=views,
                    co_authors=co_authors or [], content_details=content_details or {},
                    review_notes=review_notes, is_featured=is_featured,
                    published_at=now if published else None,
                    created_at=now, updated_at=now,
                ),
            )
            if tags:
                article.tags.set([t for t in tags if t])
            return article

        # Fariha — one published paper, one disease update needing revision
        paper1 = make_article(
            author=fariha, content_type='research_paper',
            title='Optimal Vaccination Timing for Newcastle Disease in Commercial Broilers',
            abstract='A field study across twelve commercial broiler farms evaluating the effect of '
                     'vaccination timing on Newcastle disease titres and mortality outcomes.',
            body='Introduction: Newcastle disease remains one of the most economically significant viral '
                 'diseases affecting commercial poultry in Bangladesh...\n\n'
                 'Methods: Twelve broiler farms were enrolled and randomly assigned to three vaccination '
                 'schedules (day 7, day 14, day 21) using a live LaSota strain vaccine...\n\n'
                 'Results: Farms vaccinated on day 7 showed significantly higher antibody titres at day 28 '
                 '(p<0.01) and a 34% reduction in mortality compared to the day 21 group...\n\n'
                 'Conclusion: Early vaccination at day 7 is recommended for high-risk zones with a history '
                 'of Newcastle disease outbreaks.',
            category='disease', keywords=['newcastle', 'vaccination', 'broiler'],
            farmer_summary='Vaccinate broiler chicks against Newcastle disease as early as day 7, especially '
                            'if your area has had past outbreaks — this cut mortality by a third in our trial.',
            status='published', co_authors=['Dr. Kamal Uddin - Bangladesh Agricultural University'],
            tags=[newcastle, broiler, vaccination], is_featured=True, views=482, published=True,
        )
        disease1 = make_article(
            author=fariha, content_type='disease_study',
            title='Fowl Pox Outbreak Patterns in Backyard Flocks',
            abstract='Fowl pox outbreak notes',
            body='Supportive care and isolation of affected birds from the flock.',
            category='disease', keywords=['fowl pox'],
            farmer_summary='Isolate affected birds immediately and disinfect shared equipment.',
            status='needs_revision',
            content_details={'symptoms': 'Wart-like lesions on the comb, wattle, and unfeathered skin.',
                              'treatment': 'No specific antiviral treatment; supportive care and secondary '
                                           'infection control with topical antiseptics.',
                              'prevention': 'Vaccinate at day-old and control biting insect vectors.'},
            tags=[newcastle], review_notes='Please add data on affected breed distribution and a source citation before this can be approved.',
        )

        # Mahmud — one published + featured innovation, one paper pending review
        innovation1 = make_article(
            author=mahmud, content_type='innovation',
            title='Low-Cost Automated Feed Dispenser for Smallholder Broiler Sheds',
            abstract='An Arduino-based automated feed dispenser built from locally available parts, '
                     'reducing daily labor time by an estimated 40% on a 2,000-bird shed.',
            body='The dispenser uses a low-cost microcontroller, a gravity-fed hopper, and a timed auger '
                 'motor to distribute feed across four feeding lines on a fixed schedule...\n\n'
                 'Field trials across three smallholder sheds showed feed wastage dropped from 8% to 3% '
                 'and labor time fell from 90 minutes/day to roughly 55 minutes/day.',
            category='nutrition', keywords=['automation', 'feed efficiency'],
            farmer_summary='A simple, low-cost automated feeder can cut your daily feeding labor almost in '
                            'half and reduce feed wastage — parts cost under ৳8,000 to build.',
            status='published',
            content_details={'source_details': 'In-house prototype, field-tested on three partner farms.',
                              'media_urls': ['https://example.com/media/feeder-prototype.jpg']},
            tags=[automation, feed], is_featured=True, views=317, published=True,
        )
        paper2 = make_article(
            author=mahmud, content_type='research_paper',
            title='Locally Sourced Protein Alternatives in Layer Feed Formulation',
            abstract='Evaluating black soldier fly larvae meal as a partial replacement for soybean meal '
                     'in layer diets, measuring egg production and feed conversion ratio over 16 weeks.',
            body='Introduction: Soybean meal price volatility has driven interest in locally producible '
                 'alternative protein sources for layer diets...\n\n'
                 'Methods: 240 layers were divided into four groups receiving 0%, 10%, 20%, and 30% '
                 'black soldier fly larvae meal replacing soybean meal...\n\n'
                 'Results: The 20% inclusion group matched control-group egg production with no significant '
                 'difference in feed conversion ratio, while reducing feed cost per dozen eggs by 6%.',
            category='nutrition', keywords=['feed formulation', 'layer', 'protein'],
            farmer_summary='Replacing up to 20% of soybean meal with black soldier fly larvae meal can cut '
                            'feed costs without hurting egg production.',
            status='pending_review', tags=[layer, feed],
        )

        # Sabiha — unverified, has only a draft (cannot submit yet)
        draft1 = make_article(
            author=sabiha, content_type='disease_study',
            title='Preliminary Notes on Vaccine Response Variability in Layer Flocks',
            abstract='Early observations on antibody titre variability following routine vaccination.',
            body='Draft notes pending further data collection.',
            category='disease', keywords=['vaccine'],
            farmer_summary='', status='draft',
            content_details={'symptoms': '', 'treatment': '', 'prevention': ''},
        )

        # ── Team Featherflow announcement, published by the research admin ─
        team_update = make_article(
            author=research_admin, content_type='team_update',
            title='Featherflow Researchers Panel: New Tools for Verified Researchers',
            abstract='We have rolled out tag-based search, version history, and a formal profile-appeal '
                     'process for verified researchers.',
            body='This release adds a constrained tag catalog for papers, disease updates, and innovations, '
                 'a version history viewer, and a way to request changes to verified profile fields through '
                 'admin review. Thank you for helping build a trustworthy poultry knowledge base.',
            category=None, keywords=[], farmer_summary='', status='published',
            is_featured=True, views=120, published=True,
        )

        # ── Version history snapshots for the non-draft items ─────────────
        for article, note in ((disease1, 'Submitted for review'), (paper2, 'Submitted for review'),
                               (paper1, 'Published by admin')):
            ArticleVersionSnapshot.objects.get_or_create(
                article=article, version=1,
                defaults={
                    'id': uuid.uuid4(),
                    'snapshot': {'title': article.title, 'abstract': article.abstract, 'status': article.status},
                    'changed_by': article.author, 'change_note': note, 'changed_at': now,
                },
            )

        # ── Bookmarks from the farmer account ─────────────────────────────
        Bookmark.objects.get_or_create(user=farmer, target_id=paper1.id, target_type='article',
                                        defaults={'id': uuid.uuid4(), 'created_at': now})
        Bookmark.objects.get_or_create(user=farmer, target_id=innovation1.id, target_type='article',
                                        defaults={'id': uuid.uuid4(), 'created_at': now})

        # ── Profile change applications (pending / approved / rejected) ───
        ProfileChangeApplication.objects.get_or_create(
            user=fariha, field_name='department', status='pending',
            defaults={'id': uuid.uuid4(), 'old_value': 'Poultry Science',
                      'new_value': 'Poultry Science and Avian Health',
                      'reason': 'Our department was renamed after the faculty restructuring this year.',
                      'created_at': now, 'updated_at': now},
        )
        approved_app, created = ProfileChangeApplication.objects.get_or_create(
            user=mahmud, field_name='institution_name', status='approved',
            defaults={'id': uuid.uuid4(), 'old_value': 'BAU', 'new_value': 'Bangladesh Agricultural University',
                      'reason': 'Using the full official institution name.', 'reviewed_by': research_admin,
                      'review_note': 'Confirmed against staff directory.', 'decided_at': now,
                      'created_at': now, 'updated_at': now},
        )
        ProfileChangeApplication.objects.get_or_create(
            user=fariha, field_name='graduation_year', status='rejected',
            defaults={'id': uuid.uuid4(), 'old_value': '2019', 'new_value': '2018',
                      'reason': 'Correcting a typo from signup.', 'reviewed_by': research_admin,
                      'review_note': 'Please provide a scan of your degree certificate to confirm the year.',
                      'decided_at': now, 'created_at': now, 'updated_at': now},
        )

        # ── Content report awaiting admin review ──────────────────────────
        Report.objects.get_or_create(
            reporter=farmer, target_id=innovation1.id, target_type='article', status='pending',
            defaults={'id': uuid.uuid4(), 'reason': 'The cost estimate in this post seems outdated — '
                                                     'parts cost a lot more than ৳8,000 now.',
                      'created_at': now, 'updated_at': now},
        )

        self.stdout.write(self.style.SUCCESS(
            'Seeded Researchers Panel demo data.\n'
            f'  Password for every demo account: {PASSWORD}\n'
            '  Researchers:\n'
            '    research.fariha@example.com   — verified, premium, 1 published + 1 needs_revision\n'
            '    research.mahmud@example.com   — verified, premium, 1 published+featured + 1 pending_review\n'
            '    research.sabiha@example.com   — NOT verified, 1 draft (cannot submit yet)\n'
            '  Admin:\n'
            '    admin.research@example.com    — admin_research (content moderation, applications, reports)\n'
            '  Also seeded: 1 published Team Featherflow update, 2 bookmarks (farmer.rashed@example.com), '
            '3 profile change applications (pending/approved/rejected), 1 pending content report.'
        ))
