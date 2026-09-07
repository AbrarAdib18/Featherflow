import 'package:flutter/material.dart';

class AppLocalizations {
  AppLocalizations(this.locale);
  final Locale locale;

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  bool get _bn => locale.languageCode == 'bn';

  // ── App ──────────────────────────────────────────────────────────────────
  String get appName => 'Featherflow';

  // ── Language dialog ──────────────────────────────────────────────────────
  String get selectLanguage => _bn ? 'ভাষা নির্বাচন করুন' : 'Select Language';
  String get selectLanguageHint =>
      _bn ? 'চালিয়ে যেতে পছন্দের ভাষা বেছে নিন' : 'Choose your preferred language to continue';
  String get continueBtn => _bn ? 'চালিয়ে যান' : 'Continue';
  String get cancelBtn => _bn ? 'বাতিল করুন' : 'Cancel';
  String get changeLanguage => _bn ? 'ভাষা পরিবর্তন' : 'Change Language';
  String get english => 'English';
  String get bengali => 'বাংলা';

  // ── Nav / common ─────────────────────────────────────────────────────────
  String get home => _bn ? 'হোম' : 'Home';
  String get detect => _bn ? 'শনাক্ত' : 'Detect';
  String get cost => _bn ? 'খরচ' : 'Cost';
  String get community => _bn ? 'সম্প্রদায়' : 'Community';
  String get profile => _bn ? 'প্রোফাইল' : 'Profile';

  // ── Dashboard ────────────────────────────────────────────────────────────
  String get welcomeBack => _bn ? 'ফিরে আসুন' : 'Welcome back';
  String get diseaseDetectionGrid => _bn ? 'রোগ\nশনাক্তকরণ' : 'Disease\nDetection';
  String get costManagementGrid => _bn ? 'খরচ\nব্যবস্থাপনা' : 'Cost\nManagement';
  String get findVetGrid => _bn ? 'পশুচিকিৎসক\nখুঁজুন' : 'Find\nVet';
  String get communityGrid => _bn ? 'সম্প্রদায়' : 'Community';
  String get feedManagementGrid => _bn ? 'খাদ্য\nব্যবস্থাপনা' : 'Feed\nManagement';
  String get laborManagementGrid => _bn ? 'শ্রম\nব্যবস্থাপনা' : 'Labor\nManagement';
  String get pharmacyGrid => _bn ? 'ফার্মেসি' : 'Pharmacy';
  String get articlesGrid => _bn ? 'নিবন্ধ' : 'Articles';
  String get recentAlerts => _bn ? 'সাম্প্রতিক সতর্কতা' : 'Recent Alerts';
  String get farmStats => _bn ? 'খামার পরিসংখ্যান' : 'Farm Stats';
  String get totalBirds => _bn ? 'মোট পাখি' : 'Total Birds';
  String get activeBatches => _bn ? 'সক্রিয় ব্যাচ' : 'Active Batches';
  String get healthStatus => _bn ? 'স্বাস্থ্য অবস্থা' : 'Health Status';
  String get good => _bn ? 'ভালো' : 'Good';

  // alerts
  String get alertLowFeed => _bn ? 'কম খাদ্য মজুদ' : 'Low Feed Stock';
  String get alertLowFeedDesc =>
      _bn ? 'শেড বি — মাত্র ২ দিনের মজুদ বাকি' : 'Shed B — Only 2 days remaining';
  String get alertHealth => _bn ? 'স্বাস্থ্য সতর্কতা' : 'Health Alert';
  String get alertHealthDesc =>
      _bn ? '৩টি পাখির শ্বাসকষ্টের লক্ষণ' : '3 birds showing respiratory symptoms';
  String get alertVaccination => _bn ? 'টিকা সম্পন্ন' : 'Vaccination Done';
  String get alertVaccinationDesc =>
      _bn ? 'ব্যাচ #৩ টিকা সম্পন্ন হয়েছে' : 'Batch #3 vaccination completed';
  String get timeAgo2h => _bn ? '২ ঘণ্টা আগে' : '2h ago';
  String get timeAgo5h => _bn ? '৫ ঘণ্টা আগে' : '5h ago';
  String get timeAgo1d => _bn ? '১ দিন আগে' : '1d ago';

  // pro banner
  String get becomeProFarmer => _bn ? 'প্রো কৃষক হন' : 'Become a Pro Farmer';
  String get proFarmerSubtitle =>
      _bn ? 'সীমাহীন স্ক্যান, পশুচিকিৎসক বুকিং এবং আরও অনেক কিছু' : 'Unlock unlimited scans, vet booking & more';

  // ── Disease detection ────────────────────────────────────────────────────
  String get diseaseDetection => _bn ? 'রোগ শনাক্তকরণ' : 'Disease Detection';
  String get freeScansBadge => _bn ? '৩টি বিনামূল্যে স্ক্যান বাকি' : '3 free scans left';
  String get uploadImage => _bn ? 'ছবি আপলোড করুন' : 'Upload Image';
  String get dropChickenImage =>
      _bn ? 'এখানে মুরগির ছবি ফেলুন' : 'Drop chicken image here';
  String get chooseFile => _bn ? 'ফাইল বেছে নিন' : 'Choose File';
  String get clearImagesHint =>
      _bn ? 'সঠিক ফলাফলের জন্য ভালো আলোর স্পষ্ট ছবি ব্যবহার করুন'
          : 'Use well-lit, clear images for accurate results';
  String get detectionResult => _bn ? 'রোগ শনাক্তের ফলাফল' : 'Detection Result';
  String get recentCases => _bn ? 'সাম্প্রতিক ঘটনা' : 'Recent Cases';
  String get freeScansUsedUp => _bn ? 'বিনামূল্যে স্ক্যান শেষ' : 'Free scans used up';
  String get upgradeToContinue =>
      _bn ? 'স্ক্যান চালিয়ে যেতে আপগ্রেড করুন' : 'Upgrade to continue scanning';
  String get viewPlans => _bn ? 'প্ল্যান দেখুন' : 'View Plans';
  String get findVetNearby => _bn ? 'কাছের পশুচিকিৎসক খুঁজুন' : 'Find Vet Nearby';
  String get askChatbot => _bn ? 'চ্যাটবট জিজ্ঞেস করুন' : 'Ask Chatbot';
  String get bookVet => _bn ? 'পশুচিকিৎসক বুক করুন' : 'Book Vet';
  String get analyzeImage => _bn ? 'ছবি বিশ্লেষণ করুন' : 'Analyze Image';
  String get removeImage => _bn ? 'সরান' : 'Remove';
  String get mlComingSoonTitle =>
      _bn ? 'এআই মডেল শীঘ্রই আসছে' : 'ML model coming soon';
  String get mlComingSoonBody => _bn
      ? 'রোগ শনাক্তকরণের এআই মডেলটি এখনও তৈরি হচ্ছে। খুব শিগগিরই চালু হবে!'
      : 'The disease detection ML model is still under development. Coming soon!';
  String get chatbotComingSoon => _bn
      ? 'এআই সহায়ক চ্যাটবট শীঘ্রই আসছে।'
      : 'The AI assistant chatbot is coming soon.';
  String get noPreviousScans =>
      _bn ? 'এখনও কোনো স্ক্যান নেই' : 'No previous scans yet';
  String get confidence => _bn ? 'নিশ্চিততা: ' : 'Confidence: ';
  String get whatToDo => _bn ? 'কী করবেন' : 'What To Do';
  String get doNotDo => _bn ? 'কী করবেন না' : 'Do Not Do';

  // case table headers
  String get caseDate => _bn ? 'তারিখ' : 'Date';
  String get caseCase => _bn ? 'ঘটনা' : 'Case';
  String get caseConfidence => _bn ? 'নিশ্চিততা' : 'Confidence';
  String get caseStatus => _bn ? 'অবস্থা' : 'Status';
  String get caseAction => _bn ? 'ক্রিয়া' : 'Action';
  String get caseView => _bn ? 'দেখুন' : 'View';

  // status labels
  String get statusDetected => _bn ? 'শনাক্ত' : 'Detected';
  String get statusSuspected => _bn ? 'সন্দেহজনক' : 'Suspected';
  String get statusClear => _bn ? 'স্বাস্থ্যকর' : 'Clear';

  // ── Profile ───────────────────────────────────────────────────────────────
  String get myProfile => _bn ? 'আমার প্রোফাইল' : 'My Profile';
  String get farmer => _bn ? 'কৃষক' : 'Farmer';
  String get farmDetails => _bn ? 'খামারের বিবরণ' : 'Farm Details';
  String get accountDetails => _bn ? 'অ্যাকাউন্টের বিবরণ' : 'Account Details';
  String get subscription => _bn ? 'সাবস্ক্রিপশন' : 'Subscription';
  String get settings => _bn ? 'সেটিংস' : 'Settings';
  String get editProfile => _bn ? 'প্রোফাইল সম্পাদনা' : 'Edit Profile';
  String get changePassword => _bn ? 'পাসওয়ার্ড পরিবর্তন' : 'Change Password';
  String get notificationSettings => _bn ? 'বিজ্ঞপ্তি সেটিংস' : 'Notification Settings';
  String get languagePreference => _bn ? 'ভাষা পছন্দ' : 'Language Preference';
  String get privacyPolicy => _bn ? 'গোপনীয়তা নীতি' : 'Privacy Policy';
  String get termsOfService => _bn ? 'সেবার শর্তাবলী' : 'Terms of Service';
  String get logout => _bn ? 'লগআউট' : 'Logout';
  String get upgrade => _bn ? 'আপগ্রেড' : 'Upgrade';
  String get proPlan => _bn ? 'প্রো প্ল্যান' : 'Pro Plan';
  String get expires => _bn ? 'মেয়াদ শেষ: ৩১ ডিসে ২০২৬' : 'Expires: 31 Dec 2026';

  // farm info labels
  String get farmType => _bn ? 'খামারের ধরন' : 'Farm Type';
  String get farmTypeValue => _bn ? 'পোল্ট্রি — ব্রয়লার' : 'Poultry — Broiler';
  String get workers => _bn ? 'কর্মী' : 'Workers';
  String get experience => _bn ? 'অভিজ্ঞতা' : 'Experience';
  String get experienceValue => _bn ? '৮ বছর' : '8 Years';
  String get email => _bn ? 'ইমেইল' : 'Email';
  String get phone => _bn ? 'ফোন' : 'Phone';
  String get memberSince => _bn ? 'সদস্য হওয়ার তারিখ' : 'Member Since';

  // ── Disease detection — action items ─────────────────────────────────────
  String get severityHigh => _bn ? 'উচ্চ' : 'High';
  String get actionIsolate =>
      _bn ? 'আক্রান্ত পাখিদের অবিলম্বে আলাদা করুন' : 'Isolate affected birds immediately';
  String get actionHydration =>
      _bn ? 'পর্যাপ্ত পানীয় জল নিশ্চিত করুন' : 'Ensure adequate hydration';
  String get actionTemperature =>
      _bn ? 'প্রতিদিন ঝাঁকের তাপমাত্রা পর্যবেক্ষণ করুন' : 'Monitor flock temperature daily';
  String get actionNoSelfMed =>
      _bn ? 'পশুচিকিৎসকের পরামর্শ ছাড়া নিজে ওষুধ দেবেন না' : 'Avoid self-medication without vet advice';

  // ── Subscription screen ───────────────────────────────────────────────────
  String get featherflowPlans => _bn ? 'ফেদারফ্লো পরিকল্পনা' : 'Featherflow Plans';
  String get upgradeFarmExperience =>
      _bn ? 'আপনার খামারের অভিজ্ঞতা উন্নত করুন' : 'Upgrade your farm experience';
  String get chooseYourPlan => _bn ? 'আপনার পরিকল্পনা বেছে নিন' : 'Choose your plan';
  String get subscriptionSubtitle => _bn
      ? 'প্রিমিয়াম সুবিধা পান: সীমাহীন রোগ স্ক্যান, খরচ ব্যবস্থাপনা, পশুচিকিৎসক বুকিং এবং আরও।'
      : 'Unlock premium features including unlimited disease scans, cost management, vet booking, tax calculator, and more.';
  String get monthly => _bn ? 'মাসিক' : 'Monthly';
  String get yearly => _bn ? 'বার্ষিক' : 'Yearly';
  String get save20 => _bn ? '২০% সাশ্রয়' : 'Save 20%';
  String get comparePlans => _bn ? 'পরিকল্পনা তুলনা' : 'Compare plans';
  String get commonQuestions => _bn ? 'সাধারণ প্রশ্ন' : 'Common questions';
  String get paymentsSecured =>
      _bn ? 'বিকাশ, নগদ, বা কার্ডের মাধ্যমে পেমেন্ট সুরক্ষিত'
          : 'Payments secured via bKash, Nagad, or card';
  String get cancelAnytime =>
      _bn ? 'যেকোনো সময় বাতিল করুন। কোনো লুকানো চার্জ নেই।' : 'Cancel anytime. No hidden fees.';
  String get mostPopular => _bn ? 'সবচেয়ে জনপ্রিয়' : 'Most Popular';
  String get featureHeader => _bn ? 'বৈশিষ্ট্য' : 'Feature';

  // plan taglines
  String get freePlanTagline => _bn ? 'মূল সুবিধা দিয়ে শুরু করুন' : 'Get started with the basics';
  String get proPlanTagline => _bn ? 'একজন গুরুতর কৃষকের জন্য সব কিছু' : 'Everything a serious farmer needs';
  String get researchPlanTagline =>
      _bn ? 'গবেষক এবং উন্নত কৃষক পরিচালকদের জন্য' : 'For researchers and advanced farm operators';

  // plan button labels
  String get currentPlan => _bn ? 'বর্তমান পরিকল্পনা' : 'Current Plan';
  String get getPro => _bn ? 'প্রো নিন' : 'Get Pro';
  String get getResearch => _bn ? 'রিসার্চ নিন' : 'Get Research';

  // plan features — Free
  String get feat3Scans => _bn ? '৩টি রোগ ছবি স্ক্যান' : '3 disease image scans';
  String get featBasicDashboard => _bn ? 'বেসিক কৃষক ড্যাশবোর্ড' : 'Basic farmer dashboard';
  String get featCommunityRead => _bn ? 'সম্প্রদায় দেখুন (পড়া মাত্র)' : 'Community view (read only)';
  String get featPaperPortal => _bn ? 'পেপার পোর্টাল অ্যাক্সেস' : 'Paper portal access';
  String get featCostMgmt => _bn ? 'খরচ ব্যবস্থাপনা' : 'Cost management';
  String get featVetBooking => _bn ? 'পশুচিকিৎসক বুকিং' : 'Vet booking';
  String get featTaxCalc => _bn ? 'ট্যাক্স ক্যালকুলেটর' : 'Tax calculator';
  String get featUnlimitedScans => _bn ? 'সীমাহীন স্ক্যান' : 'Unlimited scans';

  // plan features — Pro
  String get featUnlimitedDisease => _bn ? 'সীমাহীন রোগ স্ক্যান' : 'Unlimited disease scans';
  String get featFullCost => _bn ? 'সম্পূর্ণ খরচ ব্যবস্থাপনা' : 'Full cost management';
  String get featVetMap => _bn ? 'পশুচিকিৎসক বুকিং ও মানচিত্র' : 'Vet booking & map';
  String get featFeedLabor => _bn ? 'খাদ্য ও শ্রম ব্যবস্থাপনা' : 'Feed & labor management';
  String get featCommunityPost => _bn ? 'সম্প্রদায়ে পোস্ট করুন' : 'Community posting';
  String get featPrioritySupport => _bn ? 'অগ্রাধিকার সহায়তা' : 'Priority support';
  String get featResearcherPanel => _bn ? 'গবেষক প্যানেল' : 'Researcher panel';
  String get featPaperPublishing => _bn ? 'পেপার প্রকাশনা' : 'Paper publishing';

  // plan features — Research
  String get featEverythingInPro => _bn ? 'প্রো-র সব কিছু' : 'Everything in Pro';
  String get featResearcherPanelAccess =>
      _bn ? 'গবেষক প্যানেল অ্যাক্সেস' : 'Researcher panel access';
  String get featPaperSubmit =>
      _bn ? 'পেপার জমা ও প্রকাশনা' : 'Paper submission & publishing';
  String get featResearchAnalytics => _bn ? 'গবেষণা বিশ্লেষণ' : 'Research analytics';
  String get featCollaboration => _bn ? 'সহযোগিতার সরঞ্জাম' : 'Collaboration tools';
  String get featVerifiedBadge =>
      _bn ? 'যাচাইকৃত গবেষক ব্যাজ' : 'Verified researcher badge';

  // comparison table rows [feature, free, pro, research]
  List<List<String>> get comparisonRows => [
    [_bn ? 'রোগ স্ক্যান' : 'Disease Scans', _bn ? 'মাত্র ৩' : '3 only', '✓', '✓'],
    [_bn ? 'খরচ ব্যবস্থাপনা' : 'Cost Management', '✗', '✓', '✓'],
    [_bn ? 'পশুচিকিৎসক বুকিং' : 'Vet Booking', '✗', '✓', '✓'],
    [_bn ? 'ট্যাক্স ক্যালকুলেটর' : 'Tax Calculator', '✗', '✓', '✓'],
    [_bn ? 'সম্প্রদায়ে পোস্ট' : 'Community Posting', '✗', '✓', '✓'],
    [_bn ? 'খাদ্য ব্যবস্থাপনা' : 'Feed Management', '✗', '✓', '✓'],
    [_bn ? 'গবেষক প্যানেল' : 'Researcher Panel', '✗', '✗', '✓'],
    [_bn ? 'পেপার প্রকাশনা' : 'Paper Publishing', '✗', '✗', '✓'],
    [_bn ? 'অগ্রাধিকার সহায়তা' : 'Priority Support', '✗', '✓', '✓'],
  ];

  // FAQ
  String get faq1Q => _bn ? 'পরে কি পরিকল্পনা পরিবর্তন করতে পারবো?' : 'Can I switch plans later?';
  String get faq1A => _bn
      ? 'হ্যাঁ, আপনি যেকোনো সময় এই স্ক্রিন থেকে আপগ্রেড বা ডাউনগ্রেড করতে পারবেন। পরিবর্তন পরবর্তী বিলিং সাইকেলের শুরুতে কার্যকর হবে।'
      : 'Yes, you can upgrade or downgrade at any time from this screen. Changes take effect at the start of your next billing cycle.';
  String get faq2Q => _bn
      ? 'বিনামূল্যে স্ক্যান শেষ হলে কী হবে?'
      : 'What happens when my free scans run out?';
  String get faq2A => _bn
      ? 'রোগ শনাক্তকরণ চালিয়ে যাওয়ার আগে একটি পরিকল্পনা বেছে নিতে আপনাকে এই পেজে পাঠানো হবে।'
      : 'You will be redirected to this page to choose a plan before continuing with disease detection.';
  String get faq3Q =>
      _bn ? 'আমার পেমেন্ট তথ্য কি নিরাপদ?' : 'Is my payment information safe?';
  String get faq3A => _bn
      ? 'হ্যাঁ। সমস্ত পেমেন্ট সুরক্ষিত গেটওয়ের মাধ্যমে প্রক্রিয়াকরণ করা হয়। ফেদারফ্লো আপনার কার্ড বা ওয়ালেটের তথ্য সংরক্ষণ করে না।'
      : 'Yes. All payments are processed through secured gateways. Featherflow does not store your card or wallet details.';
}

// ── Delegate ─────────────────────────────────────────────────────────────────

class AppLocalizationsDelegate extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'bn'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(_) => false;
}
