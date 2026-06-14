import 'models/research_paper.dart';
import 'models/disease_update.dart';
import 'models/innovation_post.dart';
import 'models/researcher_profile.dart';

const demoResearcherProfile = ResearcherProfile(
  id: 'r1',
  name: 'Dr. Ahmed Rahman',
  email: 'researcher@gmail.com',
  institution: 'Bangladesh Agricultural University',
  department: 'Department of Poultry Science',
  specialty: 'Poultry Health & Infectious Disease Management',
  yearsExperience: 12,
  researchInterests: [
    'Avian Influenza',
    'Gut Microbiome',
    'Alternative Proteins',
    'Poultry Welfare',
    'Disease Epidemiology',
    'Precision Nutrition',
  ],
  bio:
      'Senior researcher specializing in poultry pathology and infectious disease control with over 12 years of field and laboratory experience. Former consultant for FAO and USAID poultry development programs across South and Southeast Asia. Active member of the World Poultry Science Association.',
  isVerified: true,
  contactEmail: 'researcher@gmail.com',
  orcid: '0000-0002-1234-5678',
  linkedIn: 'linkedin.com/in/dr-ahmed-rahman',
  totalPublications: 23,
  totalCitations: 847,
  hIndex: 12,
);

const _author1 = ResearchAuthor(
  id: 'r1',
  name: 'Dr. Ahmed Rahman',
  institution: 'Bangladesh Agricultural University',
  email: 'researcher@gmail.com',
  isCorresponding: true,
);

const _author2 = ResearchAuthor(
  id: 'r2',
  name: 'Dr. Sarah Chen',
  institution: 'Wageningen University & Research',
  email: 's.chen@wur.nl',
);

const _author3 = ResearchAuthor(
  id: 'r3',
  name: 'Prof. Mohammad Hossain',
  institution: 'Bangladesh Agricultural University',
  email: 'm.hossain@bau.edu.bd',
);

const _author4 = ResearchAuthor(
  id: 'r4',
  name: 'Dr. Li Wei',
  institution: 'China Agricultural University',
  email: 'l.wei@cau.edu.cn',
);

final demoPapers = <ResearchPaper>[
  ResearchPaper(
    id: 'p1',
    title:
        'Efficacy of Black Soldier Fly Larvae as Protein Supplement in Broiler Diets',
    abstract:
        'This study investigates the partial replacement of soybean meal with dried black soldier fly larvae (BSFL) meal at 0%, 5%, 10%, and 15% inclusion levels in broiler diets and its effects on growth performance, carcass quality, and gut morphology over a 42-day production cycle. A total of 240 one-day-old Ross 308 broiler chicks were randomly allocated to four dietary treatments with six replicates of 10 birds each.',
    body: '''Background
Black soldier fly larvae (Hermetia illucens) have emerged as a promising sustainable protein source for livestock feed. With an amino acid profile comparable to soybean meal and high levels of lauric acid with known antimicrobial properties, BSFL meal presents an economically viable and ecologically sustainable alternative to conventional protein sources.

Materials & Methods
Feed composition, growth performance parameters (FCR, ADG, ADFI), blood biochemistry, ileal morphometry, and carcass yield were assessed at day 21 and day 42. Data were analyzed using one-way ANOVA with Tukey post-hoc comparison (P < 0.05).

Results
Birds receiving 10% BSFL replacement showed comparable FCR (1.67 vs 1.64 in control) with a significant (P < 0.05) reduction in abdominal fat percentage and improvement in villus height:crypt depth ratio in the ileum. The 15% inclusion group showed slightly reduced final body weight (P = 0.03) compared to control.

Conclusions
BSFL meal can safely replace up to 10% of soybean meal in broiler diets without compromising performance, while offering potential gut health benefits. Further studies on economic feasibility at larger scale are warranted.''',
    keywords: ['BSFL', 'protein', 'broiler', 'alternative feed', 'sustainability', 'gut morphology'],
    references:
        '1. Makkar HPS et al. (2014) State-of-the-art on use of insects as animal feed. Animal Feed Science and Technology 197:1-33.\n2. Schiavone A et al. (2017) Partial or total replacement of soybean oil by black soldier fly larvae fat in broiler diets. Ital J Anim Sci 16(1):93-100.',
    authors: [_author1, _author2, _author3],
    status: PaperStatus.published,
    field: ResearchField.nutrition,
    tags: ['Broilers', 'Protein', 'Sustainability', 'Gut Health'],
    createdAt: DateTime(2023, 8, 10),
    updatedAt: DateTime(2024, 1, 30),
    publishedAt: DateTime(2024, 2, 15),
    hasPdf: true,
    views: 1247,
    downloads: 342,
    bookmarks: 89,
    doi: '10.1016/j.psj.2024.103521',
    journal: 'Poultry Science Journal',
    versions: [
      PaperVersion(
        versionNumber: 1,
        submittedAt: DateTime(2023, 9, 5),
        changeNotes: 'Initial submission',
      ),
      PaperVersion(
        versionNumber: 2,
        submittedAt: DateTime(2024, 1, 15),
        changeNotes: 'Revised per reviewer comments – added statistical appendix',
      ),
    ],
  ),
  ResearchPaper(
    id: 'p2',
    title:
        'Genomic Analysis of Newcastle Disease Virus Strains in Commercial Poultry Farms of Bangladesh',
    abstract:
        'Whole-genome sequencing of 47 NDV isolates from outbreak farms across six districts revealed the emergence of a novel genotype VII.2 variant with enhanced pathogenicity index (ICPI = 1.82) distinct from the vaccine strain La Sota. Phylogenetic analysis indicates regional spread consistent with migratory bird pathways.',
    body: '''Introduction
Newcastle disease remains one of the most economically devastating viral diseases in poultry worldwide. The emergence of new genotypes that diverge antigenically from commercial vaccine strains presents a significant challenge for disease control programs in Bangladesh.

Methods
Samples were collected from 12 commercial farms experiencing outbreaks between January and October 2023. Complete fusion protein gene sequencing and full-genome assembly were performed using Illumina MiSeq. Pathotyping was confirmed by intracerebral pathogenicity index (ICPI) in 1-day-old SPF chicks.

Preliminary Results
Of 47 isolates, 38 (81%) clustered within Genotype VII.2 based on full F-gene phylogeny. Mean ICPI was 1.82 ± 0.11. HI assays showed 4-8-fold reduced reactivity against La Sota antiserum compared to homologous antigen. Phylogeographic analysis suggests Genotype VII.2 entry via the Sundarbans migratory corridor.

Status Note
This paper is currently under peer review. Reviewer comments are expected within 6-8 weeks.''',
    keywords: ['Newcastle disease', 'NDV', 'genomics', 'genotype VII.2', 'Bangladesh', 'phylogeny'],
    references:
        '1. Dimitrov KM et al. (2019) Updated unified phylogenetic classification system and revised nomenclature for Newcastle disease virus. Infect Genet Evol 74:103917.\n2. Islam MdR et al. (2020) Isolation and characterization of avian paramyxovirus type-1 in Bangladesh. J Vet Sci 21(4):e62.',
    authors: [_author1, _author4],
    status: PaperStatus.underReview,
    field: ResearchField.disease,
    tags: ['Newcastle Disease', 'Virology', 'Genomics', 'Broilers', 'Layers'],
    createdAt: DateTime(2024, 9, 1),
    updatedAt: DateTime(2024, 11, 20),
    hasPdf: true,
    views: 312,
    downloads: 47,
    bookmarks: 28,
    journal: 'Avian Pathology',
    versions: [
      PaperVersion(
        versionNumber: 1,
        submittedAt: DateTime(2024, 11, 20),
        changeNotes: 'Initial submission',
      ),
    ],
  ),
  ResearchPaper(
    id: 'p3',
    title:
        'Precision Ventilation Control Using LSTM Neural Networks in Commercial Broiler Houses',
    abstract:
        'A long short-term memory (LSTM) recurrent neural network model was trained on 18 months of environmental sensor data from two commercial broiler houses to dynamically optimize ventilation parameters. The model reduced heat stress mortality by 34% and feed conversion degradation during heat events by 18% compared to conventional rule-based control systems.',
    body: '''Background
Heat stress in broiler production causes estimated annual losses exceeding US\$128 million in South Asian markets. Static thermostat-based ventilation control systems fail to account for real-time interactions between bird density, metabolic heat output, outdoor humidity, and solar gain.

System Architecture
Sensors measured: ambient temperature (±0.1°C), relative humidity (±2%), CO2 ppm, NH3 ppm, litter moisture, and bird activity via infrared motion sensors at 1-minute intervals. The LSTM model processed 72-hour rolling windows to predict 4-hour ahead thermal comfort index (TCI) and commanded variable-speed fan controllers accordingly.

Performance
Over a 6-flock validation trial (36 weeks), the LSTM-controlled house showed 34% lower mortality during peak summer weeks vs. paired control house (0.8% vs. 1.22%). Final body weight at 35 days was 2.21 kg ± 0.08 vs. 2.14 kg ± 0.11 in control (P = 0.028). Energy cost for ventilation decreased 12% due to better anticipatory ramp-up vs. reactive on/off cycling.''',
    keywords: ['ventilation', 'LSTM', 'heat stress', 'IoT', 'broiler house', 'precision farming'],
    references:
        '1. Costantino A et al. (2020) A review of livestock indoor climate control systems. Energies 13(6):1372.\n2. Kim J et al. (2022) Deep learning for livestock monitoring: A review. Comp Electron Agric 195:106855.',
    authors: [_author1, _author2],
    status: PaperStatus.accepted,
    field: ResearchField.automation,
    tags: ['Automation', 'IoT', 'Heat Stress', 'Broilers', 'Machine Learning'],
    createdAt: DateTime(2024, 5, 14),
    updatedAt: DateTime(2024, 12, 1),
    hasPdf: true,
    views: 589,
    downloads: 91,
    bookmarks: 54,
    journal: 'Biosystems Engineering',
    versions: [
      PaperVersion(
        versionNumber: 1,
        submittedAt: DateTime(2024, 7, 10),
        changeNotes: 'Initial submission',
      ),
      PaperVersion(
        versionNumber: 2,
        submittedAt: DateTime(2024, 11, 4),
        changeNotes: 'Revised: added energy cost analysis per reviewer request',
      ),
    ],
  ),
  ResearchPaper(
    id: 'p4',
    title:
        'Comparative Gut Microbiome Analysis in Free-Range vs. Conventionally Housed Layer Hens',
    abstract:
        '16S rRNA gene sequencing of caecal contents from 240 Isa Brown layer hens revealed significantly higher microbial alpha diversity (Shannon index: 4.12 vs. 3.47, P < 0.001) and Lactobacillus abundance in free-range versus conventional cage-housed birds. Conventional housing showed elevated Clostridium perfringens colonization associated with necrotic enteritis risk.',
    body: '''Introduction
The welfare and health implications of poultry housing systems have increasingly come under regulatory scrutiny. The gut microbiome mediates nutrient absorption, immune priming, and pathogen resistance, making it a sensitive indicator of bird health status across housing systems.

Methods
120 free-range and 120 cage-housed Isa Brown hens of identical age (32 weeks) and genetic origin were sampled at three farms per system. Caecal contents were processed for DNA extraction and V3-V4 16S amplicon sequencing (Illumina MiSeq). Alpha and beta diversity metrics and differential abundance testing (DESeq2) were applied.

Results
Shannon index was significantly higher in free-range birds. LEfSe analysis identified 14 enriched taxa in free-range, including Lactobacillus salivarius, Faecalibacterium prausnitzii, and Bifidobacterium animalis. Conventional housing birds showed 3.8-fold higher Clostridium perfringens abundance (P < 0.001).

Reviewer Comments
Reviewer 1 requests additional metadata on feed composition differences between farms. Reviewer 2 requests clarification on sequencing depth and rarefaction procedure.''',
    keywords: ['microbiome', 'gut health', 'free-range', 'layers', '16S rRNA', 'Lactobacillus', 'housing systems'],
    references:
        '1. Stanley D et al. (2016) Caecal microbiota of chickens varies with the level of fishmeal inclusion. PeerJ 4:e1945.\n2. Oakley BB et al. (2014) The chicken gastrointestinal microbiome. FEMS Microbiol Lett 360(2):100-112.',
    authors: [_author1, _author3, _author4],
    status: PaperStatus.needsRevision,
    field: ResearchField.welfare,
    tags: ['Microbiome', 'Free-Range', 'Layers', 'Gut Health', 'Housing'],
    createdAt: DateTime(2024, 3, 22),
    updatedAt: DateTime(2024, 10, 5),
    views: 203,
    downloads: 19,
    bookmarks: 31,
    journal: 'Frontiers in Veterinary Science',
    reviewComments: [
      ReviewComment(
        id: 'rc1',
        reviewerName: 'Reviewer 1',
        comment:
            'The manuscript lacks adequate description of feed composition across the sampled farms. Differences in dietary fiber and prebiotic content between free-range and cage farms could confound microbiome differences attributed solely to housing system. Please provide feed analysis data or address this as a limitation.',
        createdAt: DateTime(2024, 10, 1),
        resolved: false,
      ),
      ReviewComment(
        id: 'rc2',
        reviewerName: 'Reviewer 2',
        comment:
            'Please clarify the sequencing depth per sample and the rarefaction depth used for diversity analysis. The Methods section states "minimum 10,000 reads" but Figure 2 rarefaction curves suggest some samples were rarefied at lower depth. This needs to be reconciled.',
        createdAt: DateTime(2024, 10, 3),
        resolved: false,
      ),
    ],
    versions: [
      PaperVersion(
        versionNumber: 1,
        submittedAt: DateTime(2024, 6, 18),
        changeNotes: 'Initial submission',
      ),
    ],
  ),
  ResearchPaper(
    id: 'p5',
    title:
        'Economic Impact of Coccidiosis Control Programs on Small-Scale Poultry Farms in Rural Bangladesh',
    abstract:
        'A cost-benefit analysis of anticoccidial programs (ionophore, live-oocyst vaccine, and combination) in 156 small-scale farms (500–2000 birds) over two production cycles demonstrated a mean ROI of 3.2:1 for preventive live-oocyst vaccination protocols compared to therapeutic ionophore use following clinical outbreak.',
    body: '''Background
Coccidiosis caused by Eimeria spp. is endemic in small-scale Bangladeshi poultry farms and represents a major cause of subclinical production loss. Most small farmers rely on therapeutic ionophore administration following clinical outbreak rather than preventive vaccination due to upfront cost perceptions.

Study Design
Farms were randomized into three groups: Group A (ionophore medication reactive), Group B (live-oocyst vaccination Day 1), and Group C (combination vaccine + ionophore maintenance). Total economic analysis included medication costs, mortality losses, feed conversion penalties, and veterinarian consultation fees.

Preliminary Findings
Working draft — full data analysis pending. Preliminary observations across 84 completed farm-cycles suggest Group B shows lowest total cost per kg live weight produced.''',
    keywords: ['coccidiosis', 'Eimeria', 'economics', 'small farms', 'vaccination', 'ROI', 'Bangladesh'],
    references: '',
    authors: [_author1],
    status: PaperStatus.draft,
    field: ResearchField.economics,
    tags: ['Coccidiosis', 'Small Farms', 'Economics', 'Broilers', 'Vaccination'],
    createdAt: DateTime(2024, 11, 5),
    updatedAt: DateTime(2024, 12, 10),
    views: 0,
    downloads: 0,
    bookmarks: 0,
    versions: [],
  ),
];

final demoDiseaseUpdates = <DiseaseUpdate>[
  DiseaseUpdate(
    id: 'd1',
    diseaseName: 'Highly Pathogenic Avian Influenza H5N1',
    causativeAgent: 'Influenza A Virus, subtype H5N1 (HPAI clade 2.3.4.4b)',
    symptoms:
        'Sudden mass mortality (up to 100% in 24–48h), severe respiratory distress, neurological signs (torticollis, circling, tremors), marked cyanosis of comb and wattles, severe drop in egg production, watery green diarrhea, facial edema and subcutaneous hemorrhage.',
    treatments:
        'No specific antiviral licensed for commercial poultry. Immediate depopulation of affected and contact flocks is the primary containment response. Supportive care (electrolytes, vitamins) for mildly affected birds in non-HPAI situations only. Strict movement controls and disinfection are mandatory.',
    preventionMethods:
        'Regular H5N1-specific vaccination (in endemic areas per national program), strict biosecurity (all-in/all-out, visitor control, vehicle disinfection), avoidance of contact with wild waterfowl, rodent control, immediate reporting of unusual mass mortality.',
    farmerSummary:
        'CRITICAL ALERT: If you see mass sudden death in your flock — especially alongside twisted necks, blue combs, or green diarrhea — do NOT move or sell any birds. Isolate immediately and call your veterinarian or the Department of Livestock Services within 1 hour. This disease can infect humans. Do not handle dead birds without gloves and a mask.',
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 11, 28),
    status: PaperStatus.published,
    severity: DiseaseSeverity.critical,
    affectedBreeds: ['All breeds', 'Broilers', 'Layers', 'Ducks', 'Turkeys'],
    views: 3241,
    bookmarks: 214,
  ),
  DiseaseUpdate(
    id: 'd2',
    diseaseName: 'Infectious Bronchitis Virus — Variant 793/B Detected',
    causativeAgent: 'Avian Coronavirus (IBV), serotype 793/B (also known as CR88)',
    symptoms:
        'Nasal discharge and sneezing, gasping and tracheal rales, marked egg production decline (15–30%), poor egg quality (thin-shelled, misshapen, watery albumin), swollen sinuses in young chicks, occasional nephritis in susceptible breeds.',
    treatments:
        'No specific antiviral. Supportive therapy: ensure adequate ventilation, add electrolytes and vitamin C to drinking water, reduce stocking density. Antibiotic coverage for secondary bacterial infections (E. coli, Mycoplasma) where appropriate.',
    preventionMethods:
        'Vaccination with 793/B-specific or multivalent IB vaccines from Day 1 with booster at 14–21 days. Adequate biosecurity to prevent horizontal spread. Avoid stress during peak risk periods.',
    farmerSummary:
        'If your egg production suddenly drops and eggs look watery or misshapen, check your IBV vaccination schedule with your vet immediately. A booster vaccine may be needed. This strain responds poorly to standard Massachusetts IBV vaccines.',
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 10, 14),
    status: PaperStatus.published,
    severity: DiseaseSeverity.high,
    affectedBreeds: ['Layers', 'Broilers', 'Breeders'],
    views: 1582,
    bookmarks: 97,
  ),
  DiseaseUpdate(
    id: 'd3',
    diseaseName: 'Histomoniasis (Blackhead Disease) in Free-Range Flocks',
    causativeAgent: 'Histomonas meleagridis (protozoan parasite)',
    symptoms:
        'Yellow, sulfurous diarrhea (pathognomonic), lethargy, ruffled feathers, drooping wings, anorexia, dark discoloration of the comb (hence "blackhead"), liver necrosis visible at post-mortem (sunflower lesion pattern), caecal core formation.',
    treatments:
        'Dimetridazole (restricted in many countries), ronidazole (limited availability). In countries where antiparasitic options are restricted, supportive care plus removal of earthworm habitat. Consult veterinarian for current licensed treatment options in your region.',
    preventionMethods:
        'Strict separation of turkeys and chickens (never co-range). Rotate pasture regularly to break the cecal worm (Heterakis gallinarum) life cycle. Control earthworm populations in ranging areas. Avoid wet, poorly drained soil in ranging zones.',
    farmerSummary:
        'Keep turkeys and chickens on completely separate land — never let them share the same ground. If you free-range your birds, rotate the area regularly. Sulfur-yellow droppings are the warning sign: call your vet immediately. Do not introduce new birds to an infected area without deep cleaning.',
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 8, 30),
    status: PaperStatus.published,
    severity: DiseaseSeverity.medium,
    affectedBreeds: ['Turkeys', 'Chickens (free-range)', 'Game birds'],
    views: 876,
    bookmarks: 63,
  ),
];

final demoInnovations = <InnovationPost>[
  InnovationPost(
    id: 'i1',
    title: 'AI Vision System for Early Respiratory Disease Detection in Poultry',
    summary:
        'A computer vision deep learning system (ResNet-50 backbone) trained on 120,000 annotated bird images can detect early signs of respiratory distress — such as labored breathing and neck extension — up to 48 hours before clinical symptoms become apparent to farm workers.',
    details: '''How It Works
Ceiling-mounted wide-angle cameras capture 4K video at 15 fps. The AI model performs per-bird pose estimation and breathing rate analysis using a custom attention mechanism trained to detect subtle postural changes associated with respiratory compromise.

Field Trial Results
In a trial at three 20,000-bird broiler houses in the Netherlands, the system detected two Infectious Bronchitis outbreaks 44 and 51 hours before the flock manager noticed clinical signs. Early intervention reduced mortality from 3.8% (historical average) to 1.1%.

Deployment Requirements
Requires: 4K IP cameras (1 per 1,000 m²), edge computing unit (NVIDIA Jetson AGX Orin), 1 Gbps local network. System cost approximately US\$8,000 per 10,000-bird house with 24-month ROI based on mortality reduction alone.

Availability
Currently available through SmartBird Systems (Netherlands) and licensed in 14 countries. Awaiting regulatory approval in Bangladesh and India.''',
    sourceDetails:
        'Developed by SmartBird Systems BV, Wageningen. Published in Computers and Electronics in Agriculture, Vol. 218, 2024.',
    category: InnovationCategory.diseaseControl,
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 9, 12),
    status: PaperStatus.published,
    tags: ['AI', 'Computer Vision', 'Disease Detection', 'Respiratory', 'Broilers'],
    views: 2104,
    bookmarks: 178,
  ),
  InnovationPost(
    id: 'i2',
    title: 'Precision Feed Dosing with Per-Bird Weight Tracking via IoT Load Cells',
    summary:
        'A system of precision load cells embedded under feedpan supports tracks individual feeder consumption every 15 minutes, enabling real-time feed conversion ratio calculation and automatic dosing adjustment to reduce feed waste by 18–22% without compromising body weight gain.',
    details: '''System Overview
Load cells (±1g accuracy) are installed under standard chain-feeder pan trays. A central IoT hub aggregates data from up to 256 feeder positions per house and computes real-time ADFI (average daily feed intake) per zone.

Integration
Compatible with most major automated feeding systems (Big Dutchman, Roxell, Lubing). Cloud dashboard provides daily feed consumption heatmaps, early detection of reduced intake as disease indicator (alert threshold configurable), and weekly FCR reports.

Key Results (12-flock commercial trial, Trouw Nutrition, 2023)
- Feed waste reduction: 19.4% vs. conventional ad-lib feeding
- FCR improvement: 1.68 → 1.61 (P = 0.014)
- Early disease detection (feed drop > 8% vs. prior 3-day average) flagged 6/7 subsequent disease events before clinical signs

Cost
Hardware investment: ~US\$1,200 per 10,000-bird house. Payback period: 1.4 flock cycles based on feed savings alone.''',
    sourceDetails:
        'Trouw Nutrition Innovation Lab, Amersfoort, Netherlands. Presented at EuroTier 2023.',
    category: InnovationCategory.feeding,
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 7, 22),
    status: PaperStatus.published,
    tags: ['IoT', 'Precision Feeding', 'Feed Waste', 'FCR', 'Automation'],
    views: 1467,
    bookmarks: 134,
  ),
  InnovationPost(
    id: 'i3',
    title: 'Modular Climate-Controlled Housing for Small-Scale Tropical Farms Under US\$2,000',
    summary:
        'A FAO-developed modular housing design for 500–1,000 bird flocks in tropical climates uses cross-ventilation geometry, radiant-barrier roofing, and evaporative cooling pads to maintain inside temperature within 3°C of outside ambient — all for under US\$2,000 capital investment.',
    details: '''Design Principles
The design uses natural cross-ventilation airflow principles (east-west orientation, 60° roof pitch) combined with inexpensive evaporative cooling pads on the windward side and ridge vents on the leeward side. Radiant barrier foil under corrugated tin roofing reduces radiant heat gain by 65%.

Construction Materials
Locally sourced bamboo framing is permissible; preferred materials are mild steel tubing and wire mesh sidewalls. Total material cost in Bangladesh context: approximately BDT 160,000 (US\$1,450) for a 12m × 8m house (500 birds at 0.19 m² per bird).

Performance Data (BRAC pilot, 12 farms, 2022-2023)
- Peak summer inside temperature: 31.4°C vs. outside 36.2°C (5°C reduction vs. 2°C for conventional open-sided houses)
- Mortality during heat events: 0.9% vs. 2.8% in control open-sided houses
- Farmer-reported cost recovery: mean 2.3 flock cycles

Construction Guide
Full plans, materials list, and construction manual available at fao.org/poultry-housing-tropics (English and Bengali versions).''',
    sourceDetails:
        'Food and Agriculture Organization of the United Nations (FAO) Technical Paper 2023. Developed with BRAC and Department of Livestock Services, Bangladesh.',
    category: InnovationCategory.housing,
    authorId: 'r1',
    authorName: 'Dr. Ahmed Rahman',
    publishedAt: DateTime(2024, 6, 5),
    status: PaperStatus.published,
    tags: ['Housing', 'Tropical', 'Small Farms', 'Heat Stress', 'Low-Cost', 'FAO'],
    views: 3089,
    bookmarks: 267,
  ),
];
