class ContributionItem {
  final String id;
  final String title;
  final String contentType;
  final String status;
  final int viewsCount;
  final int bookmarksCount;
  final DateTime? publishedAt;

  const ContributionItem({
    required this.id,
    required this.title,
    required this.contentType,
    required this.status,
    required this.viewsCount,
    required this.bookmarksCount,
    this.publishedAt,
  });

  factory ContributionItem.fromJson(Map<String, dynamic> json) => ContributionItem(
        id: json['id'].toString(),
        title: json['title']?.toString() ?? '',
        contentType: json['content_type']?.toString() ?? '',
        status: json['status']?.toString() ?? '',
        viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
        bookmarksCount: (json['bookmarks_count'] as num?)?.toInt() ?? 0,
        publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      );
}

class ResearcherProfile {
  final String id;
  final String name;
  final String email;
  final String phone;
  // Verified fields (locked after verification; edits require an appeal).
  final String institution;
  final String institutionalEmail;
  final String department;
  final String highestDegree;
  final String fieldOfStudy;
  final String universityName;
  final int graduationYear;
  final String researchRoleType;
  final List<String> researchInterests;
  final String bio;
  final String ethicsCertificateUrl;
  final bool conflictOfInterestDeclaration;
  final bool publicationConsent;
  final bool ipAgreement;
  // Always-editable fields.
  final String cvUrl;
  final String publicationsPortfolioUrl;
  final int yearsExperience;
  final String referenceName;
  final String referenceTitle;
  final String referenceEmail;
  final String contactEmail;
  // Read-only computed/status fields.
  final bool isVerified;
  final String verificationStatus;
  final bool hasPremiumSubscription;
  final bool fieldsLocked;
  final Set<String> verifiedFields;
  final int totalPublications;
  final int draftCount;
  final int pendingReviewCount;
  final int needsRevisionCount;
  final int totalViews;
  final int totalBookmarks;
  final Map<String, int> byType;
  final List<ContributionItem> contributions;

  const ResearcherProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone = '',
    required this.institution,
    this.institutionalEmail = '',
    required this.department,
    this.highestDegree = '',
    this.fieldOfStudy = '',
    this.universityName = '',
    this.graduationYear = 0,
    this.researchRoleType = '',
    required this.researchInterests,
    required this.bio,
    this.ethicsCertificateUrl = '',
    this.conflictOfInterestDeclaration = false,
    this.publicationConsent = false,
    this.ipAgreement = false,
    this.cvUrl = '',
    this.publicationsPortfolioUrl = '',
    this.yearsExperience = 0,
    this.referenceName = '',
    this.referenceTitle = '',
    this.referenceEmail = '',
    required this.contactEmail,
    required this.isVerified,
    this.verificationStatus = 'pending',
    this.hasPremiumSubscription = false,
    this.fieldsLocked = false,
    this.verifiedFields = const {},
    this.totalPublications = 0,
    this.draftCount = 0,
    this.pendingReviewCount = 0,
    this.needsRevisionCount = 0,
    this.totalViews = 0,
    this.totalBookmarks = 0,
    this.byType = const {},
    this.contributions = const [],
  });

  /// Falls back to field_of_study when no research_role_type was set.
  String get specialty => researchRoleType.isNotEmpty ? researchRoleType : fieldOfStudy;

  factory ResearcherProfile.fromJson(Map<String, dynamic> json) {
    final stats = Map<String, dynamic>.from(json['stats'] as Map? ?? {});
    final byType = Map<String, dynamic>.from(stats['by_type'] as Map? ?? {});
    return ResearcherProfile(
      id: json['id']?.toString() ?? '',
      name: json['full_name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString() ?? '',
      institution: json['institution_name']?.toString() ?? '',
      institutionalEmail: json['institutional_email']?.toString() ?? '',
      department: json['department']?.toString() ?? '',
      highestDegree: json['highest_degree']?.toString() ?? '',
      fieldOfStudy: json['field_of_study']?.toString() ?? '',
      universityName: json['university_name']?.toString() ?? '',
      graduationYear: (json['graduation_year'] as num?)?.toInt() ?? 0,
      researchRoleType: json['research_role_type']?.toString() ?? '',
      researchInterests: List<String>.from(json['areas_of_expertise'] as List? ?? []),
      bio: json['poultry_specific_experience']?.toString() ?? '',
      ethicsCertificateUrl: json['ethics_certificate_url']?.toString() ?? '',
      conflictOfInterestDeclaration: json['conflict_of_interest_declaration'] == true,
      publicationConsent: json['publication_consent'] == true,
      ipAgreement: json['ip_agreement'] == true,
      cvUrl: json['cv_url']?.toString() ?? '',
      publicationsPortfolioUrl: json['publications_portfolio_url']?.toString() ?? '',
      yearsExperience: (json['years_of_research_experience'] as num?)?.toInt() ?? 0,
      referenceName: json['reference_name']?.toString() ?? '',
      referenceTitle: json['reference_title']?.toString() ?? '',
      referenceEmail: json['reference_email']?.toString() ?? '',
      contactEmail: (json['institutional_email'] ?? json['email'] ?? '').toString(),
      isVerified: json['is_verified'] == true,
      verificationStatus: json['verification_status']?.toString() ?? 'pending',
      hasPremiumSubscription: json['has_premium_subscription'] == true,
      fieldsLocked: json['fields_locked'] == true,
      verifiedFields: Set<String>.from(json['verified_fields'] as List? ?? []),
      totalPublications: (stats['total_publications'] as num?)?.toInt() ?? 0,
      draftCount: (stats['drafts'] as num?)?.toInt() ?? 0,
      pendingReviewCount: (stats['pending_review'] as num?)?.toInt() ?? 0,
      needsRevisionCount: (stats['needs_revision'] as num?)?.toInt() ?? 0,
      totalViews: (stats['total_views'] as num?)?.toInt() ?? 0,
      totalBookmarks: (stats['total_bookmarks'] as num?)?.toInt() ?? 0,
      byType: byType.map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
      contributions: (json['contributions'] as List? ?? [])
          .map((e) => ContributionItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
    );
  }

  /// Only the always-editable fields — verified fields go through the
  /// change-application flow instead once fieldsLocked is true.
  Map<String, dynamic> toUpdateJson() => {
        'cv_url': cvUrl,
        'publications_portfolio_url': publicationsPortfolioUrl,
        'years_of_research_experience': yearsExperience,
        'reference_name': referenceName,
        'reference_title': referenceTitle,
        'reference_email': referenceEmail,
      };

  /// Includes verified fields too — only usable before verification.
  Map<String, dynamic> toFullUpdateJson() => {
        ...toUpdateJson(),
        'institution_name': institution,
        'institutional_email': institutionalEmail,
        'department': department,
        'highest_degree': highestDegree,
        'field_of_study': fieldOfStudy,
        'university_name': universityName,
        'graduation_year': graduationYear,
        'research_role_type': researchRoleType,
        'areas_of_expertise': researchInterests,
        'poultry_specific_experience': bio,
        'ethics_certificate_url': ethicsCertificateUrl,
      };
}
