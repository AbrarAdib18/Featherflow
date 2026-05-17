import '../models/article.dart';

final List<Article> demoArticles = [
  Article(
    id: '1',
    title:
        'Effect of Dietary Lysine Supplementation on Broiler Growth Performance in Tropical Climates',
    summary:
        'A 42-day feeding trial across 3 farms in Bangladesh showed a 12% improvement in feed conversion ratio when lysine levels exceeded 1.2% of diet dry matter.',
    body:
        'Feed conversion ratio (FCR) is one of the most critical performance indicators in commercial broiler production. This study investigated the effect of graded lysine supplementation on FCR, body weight gain, and carcass yield across three commercial farms in Dhaka, Rajshahi, and Chattogram divisions over 42 days.\n\nBirds receiving diets with 1.2% lysine (dry matter basis) showed a mean FCR of 1.71, compared to 1.93 in the control group receiving standard 0.9% lysine diets. Body weight gain at day 42 was 2,380g vs 2,105g respectively — a statistically significant difference (p<0.01).\n\nCarcass yield did not differ significantly between groups, though breast meat percentage was marginally higher in the supplemented group (34.2% vs 32.8%). No adverse effects on litter quality or mortality were observed. The findings suggest that lysine supplementation above standard recommendations offers measurable production benefits in tropical commercial settings.\n\nPractical implication: Farms using standard commercial broiler feeds in Bangladesh may benefit from a top-dress lysine supplement during the starter and grower phases, particularly during the hot season when voluntary feed intake is suppressed.',
    category: ArticleCategory.researchPaper,
    author: 'Dr. Farhan Hossain',
    authorRole: AuthorRole.researcher,
    source: 'Bangladesh Journal of Animal Science',
    date: DateTime(2026, 4, 28),
    readTimeMinutes: 8,
    isVerified: true,
    isFeatured: true,
    tags: ['broiler', 'feed efficiency', 'lysine', 'tropical'],
  ),
  Article(
    id: '2',
    title: 'Avian Influenza H5N1 Containment Protocol Updates — 2026 Guidelines',
    summary:
        'Updated FAO-WHO protocol mandates a 48-hour ring-culling radius and enhanced biosecurity zoning for all commercial poultry operations above 5,000 birds.',
    body:
        'Following the 2025–2026 H5N1 resurgence across Southeast Asia and Eastern Europe, the FAO-WHO Joint Expert Panel has released revised containment guidelines applicable to all signatory nations. The updated protocol replaces the 2022 framework.\n\nKey changes include a mandatory 48-hour ring-culling radius (expanded from 36 hours) for any confirmed H5N1 detection in commercial flocks exceeding 5,000 birds. Enhanced biosecurity zoning now requires three concentric control zones — Infected Zone (IZ), Surveillance Zone (SZ), and Free Zone (FZ) — with distinct movement restrictions for live birds, eggs, and personnel.\n\nBangladesh\'s Department of Livestock Services has confirmed adoption of the new protocol effective June 1, 2026. Farm operators are advised to review their biosecurity plans and update emergency contact procedures accordingly.\n\nThe updated guidelines are available for download from the FAO website. Featherflow\'s biosecurity checklist module will be updated in the next release to reflect these changes.',
    category: ArticleCategory.diseaseStudy,
    author: 'WHO Poultry Health Division',
    authorRole: AuthorRole.official,
    source: 'FAO-WHO Joint Report',
    date: DateTime(2026, 5, 1),
    readTimeMinutes: 6,
    isVerified: true,
    tags: ['avian flu', 'biosecurity', 'H5N1', 'containment'],
  ),
  Article(
    id: '3',
    title: 'Smart Coop Ventilation Systems: IoT Sensors Reduce Ammonia Levels by 34%',
    summary:
        'A pilot study across 12 layer farms found that automated sensor-driven ventilation cut ammonia concentrations below 15ppm, reducing respiratory disease incidence by 28%.',
    category: ArticleCategory.innovation,
    author: 'Anika Rahman',
    authorRole: AuthorRole.researcher,
    source: 'Poultry Tech Quarterly',
    date: DateTime(2026, 4, 15),
    readTimeMinutes: 5,
    isVerified: true,
    tags: ['IoT', 'ventilation', 'layer', 'innovation'],
  ),
  Article(
    id: '4',
    title: 'Poultry Market Price Outlook: Q3 2026 Bangladesh & Southeast Asia',
    summary:
        'Broiler farm-gate prices projected to rise 8–11% in Q3 driven by feed cost pressures and reduced imports. Layer egg prices expected to stabilise following flock recovery.',
    category: ArticleCategory.marketReport,
    author: 'Featherflow Market Research Team',
    authorRole: AuthorRole.official,
    source: 'Featherflow Insights',
    date: DateTime(2026, 5, 8),
    readTimeMinutes: 4,
    isVerified: true,
    tags: ['market', 'prices', 'broiler', 'Q3 2026'],
  ),
  Article(
    id: '5',
    title: 'Newcastle Disease Vaccination Timing: A Meta-Analysis of 47 Field Trials',
    summary:
        'Optimal primary vaccination at day 7 followed by a booster at day 21 showed 94% seroconversion rates in commercial broiler operations across South Asia.',
    category: ArticleCategory.diseaseStudy,
    author: 'Dr. Mehnaz Sultana',
    authorRole: AuthorRole.researcher,
    source: 'Veterinary Immunology Journal',
    date: DateTime(2026, 3, 19),
    readTimeMinutes: 11,
    isVerified: true,
    tags: ['Newcastle', 'vaccines', 'broiler', 'immunology'],
  ),
  Article(
    id: '6',
    title: 'Featherflow v3.2 Released — Batch Tracking & New Feed Module',
    summary:
        'The latest release introduces batch-level tracking, an overhauled feed cost calculator, and offline sync improvements for low-connectivity farms.',
    category: ArticleCategory.teamFeatherflow,
    author: 'Team Featherflow',
    authorRole: AuthorRole.team,
    source: 'Featherflow Official',
    date: DateTime(2026, 5, 10),
    readTimeMinutes: 2,
    isVerified: true,
    isTeamFeatherflow: true,
    tags: ['update', 'release', 'batch tracking'],
  ),
  Article(
    id: '7',
    title:
        'Probiotic Supplementation in Layer Diets: Effect on Egg Quality and Yolk Pigmentation',
    summary:
        'Inclusion of Lactobacillus acidophilus at 0.05% of diet improved Haugh unit scores by 7 points and deepened yolk colour from Roche score 8 to 11 over a 12-week trial.',
    category: ArticleCategory.feedStudy,
    author: 'Prof. Abdul Karim',
    authorRole: AuthorRole.researcher,
    source: 'Asian-Australasian J. of Animal Sciences',
    date: DateTime(2026, 2, 28),
    readTimeMinutes: 9,
    isVerified: true,
    tags: ['probiotics', 'layer', 'egg quality', 'feed'],
  ),
  Article(
    id: '8',
    title:
        'Record Bird Flu Outbreak Hits European Poultry Farms — What Bangladeshi Farmers Need to Know',
    summary:
        'Over 12 million birds culled in Poland and Hungary. Experts warn of potential import disruption and advise tightened biosecurity ahead of the winter migration season.',
    category: ArticleCategory.news,
    author: 'Featherflow News Desk',
    authorRole: AuthorRole.official,
    source: 'Featherflow News',
    date: DateTime(2026, 5, 11),
    readTimeMinutes: 3,
    isVerified: false,
    tags: ['bird flu', 'news', 'biosecurity', 'imports'],
  ),
];
