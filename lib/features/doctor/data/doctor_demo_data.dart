import 'models/doctor_models.dart';

const doctorProfile = DoctorProfile(
  id: 'DOC-001',
  name: 'Dr. Arif Hossain',
  specialty: 'Poultry Veterinarian',
  licenseNo: 'VET-BD-2019-4821',
  phone: '01712-334455',
  email: 'doctor@gmail.com',
  rating: 4.7,
  totalRatings: 128,
  isVerified: true,
  availability: DoctorAvailability.available,
);

final List<DoctorAppointment> demoAppointments = [
  DoctorAppointment(
    id: 'APT-001',
    farmerName: 'Kamal Hossain',
    farmName: 'Kamal Poultry Farm',
    farmerPhone: '01712345678',
    scheduledAt: DateTime.now().add(const Duration(hours: 2)),
    mode: AppointmentMode.online,
    status: AppointmentStatus.pending,
    isUrgent: true,
    fee: 500.0,
    notes: 'High mortality reported in broiler flock — suspected Newcastle',
  ),
  DoctorAppointment(
    id: 'APT-002',
    farmerName: 'Rahman Sikder',
    farmName: 'Sikder Agro Farm',
    farmerPhone: '01987654321',
    scheduledAt: DateTime.now().add(const Duration(hours: 5)),
    mode: AppointmentMode.inPerson,
    status: AppointmentStatus.accepted,
    isUrgent: false,
    fee: 800.0,
    notes: 'Routine flock health check and vaccination review',
  ),
  DoctorAppointment(
    id: 'APT-003',
    farmerName: 'Fatema Begum',
    farmName: 'Green Wings Farm',
    farmerPhone: '01811223344',
    scheduledAt: DateTime.now().subtract(const Duration(hours: 2)),
    mode: AppointmentMode.online,
    status: AppointmentStatus.completed,
    isUrgent: false,
    fee: 400.0,
    caseId: 'CASE-001',
  ),
  DoctorAppointment(
    id: 'APT-004',
    farmerName: 'Rahim Molla',
    farmName: 'Molla Hatchery & Farm',
    farmerPhone: '01611334455',
    scheduledAt: DateTime.now().add(const Duration(days: 1, hours: 9)),
    mode: AppointmentMode.offline,
    status: AppointmentStatus.pending,
    isUrgent: false,
    fee: 600.0,
    notes: 'Follow-up on biosecurity implementation',
  ),
  DoctorAppointment(
    id: 'APT-005',
    farmerName: 'Nasrin Akter',
    farmName: 'Nasrin Layer Farm',
    farmerPhone: '01733445566',
    scheduledAt: DateTime.now().add(const Duration(days: 2, hours: 10)),
    mode: AppointmentMode.online,
    status: AppointmentStatus.accepted,
    isUrgent: true,
    fee: 500.0,
    notes: 'Respiratory symptoms observed across 3 sheds',
  ),
  DoctorAppointment(
    id: 'APT-006',
    farmerName: 'Jamal Uddin',
    farmName: 'Uddin Broiler Complex',
    farmerPhone: '01855667788',
    scheduledAt: DateTime.now().subtract(const Duration(days: 2)),
    mode: AppointmentMode.inPerson,
    status: AppointmentStatus.noShow,
    isUrgent: false,
    fee: 700.0,
  ),
];

final List<DoctorCase> demoCases = [
  DoctorCase(
    id: 'CASE-001',
    appointmentId: 'APT-003',
    farmerName: 'Fatema Begum',
    farmName: 'Green Wings Farm',
    flockSize: 5000,
    birdAgeWeeks: 5,
    breed: 'Cobb 500 Broiler',
    mortalityCount: 47,
    symptoms: [
      'Respiratory distress',
      'Reduced feed intake',
      'Nasal discharge',
      'Swollen sinuses',
      'Rales on auscultation',
    ],
    diagnosis: 'Infectious Bronchitis (IB) with secondary bacterial involvement',
    treatmentPlan:
        'Broad-spectrum antibiotics for 5 days. Isolate affected birds immediately. Increase ventilation to reduce ammonia levels.',
    diseaseTags: ['Infectious Bronchitis', 'Secondary Bacterial'],
    urgency: CaseUrgency.urgent,
    status: CaseStatus.inProgress,
    feedNotes:
        'Reduce feed density by 15%. Ensure clean water with electrolytes. Remove overnight water before medicating.',
    vaccineHistory:
        'IB vaccine (H120) at day 7 via drinking water. IB booster at day 21 via spray. Newcastle at day 14.',
    biosecurityNotes:
        'Restrict external visitors. Mandatory footbath at all entry points. Sanitize water lines before each refill.',
    warnings:
        'Monitor mortality closely for next 72 hours. If mortality exceeds 100/day, escalate to Emergency status.',
    nextSteps:
        'Re-evaluate on day 5. Collect blood samples for serology. Report to district livestock officer if mortality persists.',
    createdAt: DateTime.now().subtract(const Duration(days: 1)),
    followUpDate: DateTime.now().add(const Duration(days: 4)),
    prescription: DoctorPrescription(
      id: 'PRES-001',
      caseId: 'CASE-001',
      medicines: [
        const MedicineSuggestion(
          name: 'Doxycycline Hyclate',
          dosage: '10 mg/kg body weight',
          duration: '5 days',
          notes: 'Mix in drinking water. Prepare fresh solution every 8 hours.',
        ),
        const MedicineSuggestion(
          name: 'Vitamin C + Electrolytes',
          dosage: '1 g per litre of water',
          duration: '7 days',
        ),
        const MedicineSuggestion(
          name: 'Tylosin Tartrate',
          dosage: '0.5 g per litre of water',
          duration: '3 days',
          notes: 'For secondary Mycoplasma prevention. Do not use concurrently with Doxycycline.',
        ),
      ],
      dosageNotes:
          'Administer medications in early morning fresh water. Remove overnight water first. Weigh sample birds every 2 days to adjust dose.',
      followUpInstructions:
          'If no improvement after 5 days, stop antibiotics and retest for viral cause. Schedule farm visit for lab sample collection.',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
    ),
  ),
  DoctorCase(
    id: 'CASE-002',
    appointmentId: 'APT-001',
    farmerName: 'Kamal Hossain',
    farmName: 'Kamal Poultry Farm',
    flockSize: 10000,
    birdAgeWeeks: 3,
    breed: 'Ross 308 Broiler',
    mortalityCount: 120,
    symptoms: [
      'Sudden death',
      'Bloody droppings',
      'Lethargy',
      'Loss of appetite',
      'Twisted neck (torticollis)',
    ],
    diagnosis: null,
    treatmentPlan: null,
    diseaseTags: ['Coccidiosis (suspected)', 'Newcastle Disease (suspected)'],
    urgency: CaseUrgency.emergency,
    status: CaseStatus.open,
    feedNotes: null,
    vaccineHistory:
        'Newcastle (LaSota) at hatch. No Gumboro administered. No coccidiosis prophylaxis in feed.',
    biosecurityNotes: null,
    warnings:
        'Mortality rate is 1.2% in 48 hours — critical threshold reached. Pending appointment for full clinical assessment.',
    nextSteps:
        'Await scheduled consultation in 2 hours. Collect fresh droppings in clean container for lab. Do not cull birds before assessment.',
    createdAt: DateTime.now().subtract(const Duration(hours: 6)),
    followUpDate: null,
  ),
  DoctorCase(
    id: 'CASE-003',
    appointmentId: 'APT-002',
    farmerName: 'Rahman Sikder',
    farmName: 'Sikder Agro Farm',
    flockSize: 3500,
    birdAgeWeeks: 10,
    breed: 'Sonali Cross',
    mortalityCount: 8,
    symptoms: [
      'Reduced egg production (30% drop)',
      'Pale combs and wattles',
      'Progressive weight loss',
      'Limb paralysis in 3 birds',
    ],
    diagnosis: "Marek's Disease with secondary immunosuppression-induced anaemia",
    treatmentPlan:
        "Supportive multivitamin therapy. Cull severely paralysed birds humanely. Reinforce vaccination protocol for next batch.",
    diseaseTags: ["Marek's Disease", 'Anaemia', 'Immunosuppression'],
    urgency: CaseUrgency.moderate,
    status: CaseStatus.followUp,
    feedNotes:
        'Increase dietary protein to 20% for recovery phase. Add iron supplement (ferrous sulphate) at 50ppm for 10 days.',
    vaccineHistory:
        "Marek's (HVT) vaccine at hatch. Suspected cold-chain failure during storage — temperature logger review needed.",
    biosecurityNotes:
        "Investigate vaccine refrigerator temperature logs. Source replacement flock only from certified Marek's-free hatchery.",
    warnings: null,
    nextSteps:
        'Schedule biosecurity and cold-chain audit. Run serology on 20 birds for Marek\'s titre levels. Discuss flock replacement timeline.',
    createdAt: DateTime.now().subtract(const Duration(days: 7)),
    followUpDate: DateTime.now().add(const Duration(days: 7)),
    prescription: DoctorPrescription(
      id: 'PRES-002',
      caseId: 'CASE-003',
      medicines: [
        const MedicineSuggestion(
          name: 'ADE Forte (Vitamin A, D3, E)',
          dosage: '1 ml per litre of water',
          duration: '10 days',
        ),
        const MedicineSuggestion(
          name: 'Ferrous Sulphate',
          dosage: '50 ppm in feed',
          duration: '10 days',
          notes: 'For anaemia correction. Do not exceed recommended dose.',
        ),
      ],
      dosageNotes: 'Administer vitamins in afternoon water after removing medication water.',
      followUpInstructions:
          "Monitor paralysis progression. If >5 new cases/day, consider emergency culling of entire affected shed.",
      referredTo: 'Central Livestock Disease Investigation Laboratory (CDIL)',
      createdAt: DateTime.now().subtract(const Duration(days: 7)),
    ),
  ),
  DoctorCase(
    id: 'CASE-004',
    appointmentId: 'APT-003',
    farmerName: 'Asha Mondol',
    farmName: 'Mondol Layer Farm',
    flockSize: 8000,
    birdAgeWeeks: 22,
    breed: 'White Leghorn Layer',
    mortalityCount: 2,
    symptoms: [
      'Sudden 35% egg drop over 7 days',
      'Thin-shelled and soft-shelled eggs',
      'Slight respiratory noise (mild)',
    ],
    diagnosis: 'Egg Drop Syndrome 1976 (EDS-76)',
    treatmentPlan:
        'No specific antiviral available. Supportive calcium and vitamin D3 supplementation. Monitor egg quality daily.',
    diseaseTags: ['Egg Drop Syndrome', 'EDS-76'],
    urgency: CaseUrgency.routine,
    status: CaseStatus.closed,
    feedNotes:
        'Increase oyster shell grit supplementation to 4% of feed. Add 2% limestone grit. Ensure adequate calcium:phosphorus ratio (2:1).',
    vaccineHistory:
        'EDS-76 oil-emulsion vaccine at 15 weeks. Consider annual booster before next production peak.',
    biosecurityNotes: 'No immediate biosecurity concerns. Standard protocols adequate.',
    warnings: null,
    nextSteps:
        'Monitor egg production weekly for 4 weeks. Schedule booster vaccination before next peak production cycle.',
    createdAt: DateTime.now().subtract(const Duration(days: 14)),
    followUpDate: null,
    prescription: DoctorPrescription(
      id: 'PRES-003',
      caseId: 'CASE-004',
      medicines: [
        const MedicineSuggestion(
          name: 'Calcium Gluconate + Vitamin D3',
          dosage: '2 g per litre of water',
          duration: '14 days',
        ),
        const MedicineSuggestion(
          name: 'Vitamin E + Selenium',
          dosage: '1 ml per litre of water',
          duration: '7 days',
          notes: 'Supports immune recovery and shell gland function.',
        ),
      ],
      dosageNotes: 'Administer in afternoon water. Ensure birds have free access to grit tray.',
      followUpInstructions:
          'Record daily egg numbers and grade quality. If production does not recover within 3 weeks, retest for other causes.',
      createdAt: DateTime.now().subtract(const Duration(days: 14)),
    ),
  ),
];

final List<ChatThread> demoChatThreads = [
  ChatThread(
    id: 'CHAT-001',
    farmerName: 'Kamal Hossain',
    farmName: 'Kamal Poultry Farm',
    lastMessage: 'Doctor, more birds are dying. Please respond!',
    lastMessageAt: DateTime.now().subtract(const Duration(minutes: 10)),
    unreadCount: 3,
    caseId: 'CASE-002',
    messages: [
      ChatMessage(
        id: 'MSG-001',
        fromDoctor: false,
        content: 'Doctor, I have an emergency. My chickens are dying rapidly — over 50 in the last hour.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 2)),
      ),
      ChatMessage(
        id: 'MSG-002',
        fromDoctor: true,
        content:
            'I understand the urgency. Please send me photos of the affected birds, their droppings, and the feed bag label.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 50)),
      ),
      ChatMessage(
        id: 'MSG-003',
        fromDoctor: false,
        content: '[Photo of affected birds attached]',
        type: MessageType.image,
        sentAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 40)),
      ),
      ChatMessage(
        id: 'MSG-004',
        fromDoctor: true,
        content:
            'Thank you. I can see bloody droppings and torticollis — this looks like Newcastle or severe Coccidiosis. Isolate all sick birds immediately. Restrict water for 2 hours, then provide clean medicated water. Do NOT give any antibiotics yet — wait for my full assessment.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 30)),
      ),
      ChatMessage(
        id: 'MSG-005',
        fromDoctor: false,
        content: 'Doctor, more birds are dying. Please respond!',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(minutes: 10)),
      ),
    ],
  ),
  ChatThread(
    id: 'CHAT-002',
    farmerName: 'Fatema Begum',
    farmName: 'Green Wings Farm',
    lastMessage: 'Alhamdulillah, birds are much better today, jazakallah!',
    lastMessageAt: DateTime.now().subtract(const Duration(hours: 3)),
    unreadCount: 0,
    caseId: 'CASE-001',
    messages: [
      ChatMessage(
        id: 'MSG-010',
        fromDoctor: false,
        content: 'Doctor, should I continue the doxycycline today? Some birds look better.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 4)),
      ),
      ChatMessage(
        id: 'MSG-011',
        fromDoctor: true,
        content:
            'Yes, continue the FULL 5-day course even if birds look better. Stopping early causes antibiotic resistance and relapse. Do not skip any doses.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 3, minutes: 45)),
      ),
      ChatMessage(
        id: 'MSG-012',
        fromDoctor: false,
        content: 'Alhamdulillah, birds are much better today, jazakallah!',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 3)),
      ),
    ],
  ),
  ChatThread(
    id: 'CHAT-003',
    farmerName: 'Rahman Sikder',
    farmName: 'Sikder Agro Farm',
    lastMessage: 'Understood, I will prepare all records for your visit tomorrow.',
    lastMessageAt: DateTime.now().subtract(const Duration(hours: 20)),
    unreadCount: 0,
    caseId: 'CASE-003',
    messages: [
      ChatMessage(
        id: 'MSG-020',
        fromDoctor: true,
        content:
            'Rahman bhai, I will be at your farm tomorrow at 2:00 PM for the follow-up. Please have: (1) all mortality records, (2) vaccine purchase receipts, (3) the temperature logger from your vaccine fridge.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 22)),
      ),
      ChatMessage(
        id: 'MSG-021',
        fromDoctor: false,
        content: 'Understood, I will prepare all records for your visit tomorrow.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(hours: 20)),
      ),
    ],
  ),
  ChatThread(
    id: 'CHAT-004',
    farmerName: 'Nasrin Akter',
    farmName: 'Nasrin Layer Farm',
    lastMessage: 'I noticed the breathing sounds are mostly at night.',
    lastMessageAt: DateTime.now().subtract(const Duration(days: 1)),
    unreadCount: 1,
    caseId: null,
    messages: [
      ChatMessage(
        id: 'MSG-030',
        fromDoctor: false,
        content: 'Doctor, my birds are making wheezing sounds. 3 sheds affected.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(days: 1, hours: 2)),
      ),
      ChatMessage(
        id: 'MSG-031',
        fromDoctor: true,
        content:
            'This could be Mycoplasma or IB. What is the temperature inside the shed? Any nasal discharge or swollen sinuses?',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(days: 1, hours: 1, minutes: 45)),
      ),
      ChatMessage(
        id: 'MSG-032',
        fromDoctor: false,
        content: 'I noticed the breathing sounds are mostly at night.',
        type: MessageType.text,
        sentAt: DateTime.now().subtract(const Duration(days: 1)),
      ),
    ],
  ),
];

final List<EarningsRecord> demoEarnings = [
  EarningsRecord(
    id: 'PAY-001',
    farmerName: 'Fatema Begum',
    caseId: 'CASE-001',
    amount: 400.0,
    date: DateTime.now().subtract(const Duration(hours: 2)),
    isPaid: true,
    description: 'Online consultation — IB diagnosis & prescription',
  ),
  EarningsRecord(
    id: 'PAY-002',
    farmerName: 'Asha Mondol',
    caseId: 'CASE-004',
    amount: 600.0,
    date: DateTime.now().subtract(const Duration(days: 7)),
    isPaid: true,
    description: 'In-person farm visit — EDS-76 assessment',
  ),
  EarningsRecord(
    id: 'PAY-003',
    farmerName: 'Rahman Sikder',
    caseId: 'CASE-003',
    amount: 800.0,
    date: DateTime.now().subtract(const Duration(days: 6)),
    isPaid: true,
    description: "In-person visit — Marek's disease follow-up",
  ),
  EarningsRecord(
    id: 'PAY-004',
    farmerName: 'Kamal Hossain',
    caseId: 'CASE-002',
    amount: 500.0,
    date: DateTime.now(),
    isPaid: false,
    description: 'Online consultation — Emergency Newcastle/Coccidiosis',
  ),
  EarningsRecord(
    id: 'PAY-005',
    farmerName: 'Rahim Molla',
    caseId: null,
    amount: 600.0,
    date: DateTime.now().add(const Duration(days: 1)),
    isPaid: false,
    description: 'Scheduled offline visit — biosecurity follow-up',
  ),
  EarningsRecord(
    id: 'PAY-006',
    farmerName: 'Jamal Uddin',
    caseId: null,
    amount: 0.0,
    date: DateTime.now().subtract(const Duration(days: 2)),
    isPaid: false,
    description: 'No-show — in-person appointment cancelled',
  ),
];

final List<FarmerRating> demoRatings = [
  FarmerRating(
    id: 'RAT-001',
    farmerName: 'Fatema Begum',
    rating: 5.0,
    review:
        'Dr. Arif responded immediately and diagnosed the issue correctly. My birds recovered within 5 days. Highly recommended for broiler cases!',
    date: DateTime.now().subtract(const Duration(hours: 3)),
  ),
  FarmerRating(
    id: 'RAT-002',
    farmerName: 'Asha Mondol',
    rating: 4.5,
    review:
        'Very knowledgeable about layer diseases. Explained EDS clearly and gave easy-to-follow instructions. Would consult again.',
    date: DateTime.now().subtract(const Duration(days: 10)),
  ),
  FarmerRating(
    id: 'RAT-003',
    farmerName: 'Nasrin Akter',
    rating: 5.0,
    review:
        'Excellent doctor! Responded during an emergency at midnight and guided me through the night. My flock survived. Allah bless him.',
    date: DateTime.now().subtract(const Duration(days: 20)),
  ),
  FarmerRating(
    id: 'RAT-004',
    farmerName: 'Jamal Uddin',
    rating: 4.0,
    review: 'Good consultation and accurate diagnosis. Video call had minor connection issues but resolved quickly.',
    date: DateTime.now().subtract(const Duration(days: 30)),
  ),
  FarmerRating(
    id: 'RAT-005',
    farmerName: 'Rahim Molla',
    rating: 4.5,
    review:
        'Dr. Arif knows poultry diseases very well. Gave practical advice for biosecurity improvement. Will hire again.',
    date: DateTime.now().subtract(const Duration(days: 45)),
  ),
];
