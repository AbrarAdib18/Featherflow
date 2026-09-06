enum PaperStatus { draft, underReview, needsRevision, accepted, published, archived }

PaperStatus paperStatusFromApi(String? value) => switch (value) {
      'draft' => PaperStatus.draft,
      'pending_review' => PaperStatus.underReview,
      'needs_revision' => PaperStatus.needsRevision,
      'published' => PaperStatus.published,
      'archived' => PaperStatus.archived,
      _ => PaperStatus.draft,
    };

enum ResearchField {
  nutrition,
  disease,
  breeding,
  housing,
  automation,
  welfare,
  economics,
  epidemiology,
  pharmacology,
  biosecurity,
}

extension ResearchFieldLabel on ResearchField {
  String get label => switch (this) {
        ResearchField.nutrition => 'Nutrition',
        ResearchField.disease => 'Disease',
        ResearchField.breeding => 'Breeding',
        ResearchField.housing => 'Housing',
        ResearchField.automation => 'Automation',
        ResearchField.welfare => 'Welfare',
        ResearchField.economics => 'Economics',
        ResearchField.epidemiology => 'Epidemiology',
        ResearchField.pharmacology => 'Pharmacology',
        ResearchField.biosecurity => 'Biosecurity',
      };
}

extension PaperStatusLabel on PaperStatus {
  String get label => switch (this) {
        PaperStatus.draft => 'Draft',
        PaperStatus.underReview => 'Under Review',
        PaperStatus.needsRevision => 'Needs Revision',
        PaperStatus.accepted => 'Accepted',
        PaperStatus.published => 'Published',
        PaperStatus.archived => 'Archived',
      };
}

class ReviewComment {
  final String id;
  final String reviewerName;
  final String comment;
  final DateTime createdAt;
  final bool resolved;

  const ReviewComment({
    required this.id,
    required this.reviewerName,
    required this.comment,
    required this.createdAt,
    this.resolved = false,
  });

  ReviewComment copyWith({bool? resolved}) => ReviewComment(
        id: id,
        reviewerName: reviewerName,
        comment: comment,
        createdAt: createdAt,
        resolved: resolved ?? this.resolved,
      );
}

class PaperVersion {
  final int versionNumber;
  final DateTime submittedAt;
  final String changeNotes;

  const PaperVersion({
    required this.versionNumber,
    required this.submittedAt,
    required this.changeNotes,
  });
}

class ResearchAuthor {
  final String id;
  final String name;
  final String institution;
  final String email;
  final bool isCorresponding;

  const ResearchAuthor({
    required this.id,
    required this.name,
    required this.institution,
    required this.email,
    this.isCorresponding = false,
  });

  /// Parses a free-text co-author entry like "Dr. A - Institution X".
  factory ResearchAuthor.fromCoAuthorText(String text) {
    final parts = text.split(' - ');
    return ResearchAuthor(
      id: text,
      name: parts.first.trim(),
      institution: parts.length > 1 ? parts.sublist(1).join(' - ').trim() : '',
      email: '',
    );
  }
}

ResearchField researchFieldFromApi(String? category) {
  final normalized = (category ?? '').trim().toLowerCase();
  for (final field in ResearchField.values) {
    if (field.name.toLowerCase() == normalized) return field;
  }
  return ResearchField.disease;
}

class ResearchPaper {
  final String id;
  final String title;
  final String abstract;
  final String body;
  final List<String> keywords;
  final String references;
  final List<ResearchAuthor> authors;
  final PaperStatus status;
  final ResearchField field;
  final List<String> tags;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? publishedAt;
  final bool hasPdf;
  final String? pdfUrl;
  final int views;
  final int downloads;
  final int bookmarks;
  final List<ReviewComment> reviewComments;
  final List<PaperVersion> versions;
  final String? doi;
  final String? journal;
  final List<Map<String, dynamic>> catalogTags;

  const ResearchPaper({
    required this.id,
    required this.title,
    required this.abstract,
    required this.body,
    required this.keywords,
    required this.references,
    required this.authors,
    required this.status,
    required this.field,
    required this.tags,
    required this.createdAt,
    required this.updatedAt,
    this.publishedAt,
    this.hasPdf = false,
    this.pdfUrl,
    this.views = 0,
    this.downloads = 0,
    this.bookmarks = 0,
    this.reviewComments = const [],
    this.versions = const [],
    this.doi,
    this.journal,
    this.catalogTags = const [],
  });

  factory ResearchPaper.fromJson(Map<String, dynamic> json) {
    final author = Map<String, dynamic>.from(json['author'] as Map? ?? {});
    final coAuthors = (json['co_authors'] as List? ?? [])
        .map((e) => ResearchAuthor.fromCoAuthorText(e.toString()))
        .toList();
    final createdAt =
        DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now();
    final updatedAt =
        DateTime.tryParse(json['updated_at']?.toString() ?? '') ?? createdAt;
    final reviewNotes = (json['review_notes'] ?? '').toString();
    final version = (json['version'] as num?)?.toInt() ?? 1;
    final id = json['id'].toString();
    return ResearchPaper(
      id: id,
      title: json['title']?.toString() ?? '',
      abstract: json['abstract']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      keywords: List<String>.from(json['keywords'] as List? ?? []),
      references: (json['references'] as List? ?? []).join('\n'),
      authors: [
        ResearchAuthor(
          id: author['id']?.toString() ?? '',
          name: author['name']?.toString() ?? '',
          institution: author['institution']?.toString() ?? '',
          email: '',
          isCorresponding: true,
        ),
        ...coAuthors,
      ],
      status: paperStatusFromApi(json['status']?.toString()),
      field: researchFieldFromApi(json['category']?.toString()),
      tags: [
        if ((json['category'] ?? '').toString().isNotEmpty) json['category'].toString(),
        ...List<String>.from(json['keywords'] as List? ?? []),
      ],
      createdAt: createdAt,
      updatedAt: updatedAt,
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? ''),
      hasPdf: (json['pdf_url'] ?? '').toString().isNotEmpty,
      pdfUrl: (json['pdf_url'] as String?)?.isNotEmpty == true ? json['pdf_url'] as String : null,
      views: (json['views_count'] as num?)?.toInt() ?? 0,
      downloads: (json['downloads_count'] as num?)?.toInt() ?? 0,
      bookmarks: (json['bookmarks_count'] as num?)?.toInt() ?? 0,
      reviewComments: reviewNotes.isEmpty
          ? const []
          : [
              ReviewComment(
                id: '$id-review',
                reviewerName: 'Admin review',
                comment: reviewNotes,
                createdAt: updatedAt,
              ),
            ],
      versions: List.generate(
        version,
        (i) => PaperVersion(
          versionNumber: i + 1,
          submittedAt: i == version - 1 ? updatedAt : createdAt,
          changeNotes: i == 0 ? 'Initial submission' : 'Resubmission',
        ),
      ),
      catalogTags: List<Map<String, dynamic>>.from(
          (json['tags'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
    );
  }

  /// Body sent to the backend on create/update — the API owns id/status/etc.
  Map<String, dynamic> toRequestJson({List<String>? tagIds}) => {
        'title': title,
        'abstract': abstract,
        'body': body,
        'keywords': keywords,
        'references': references.split('\n').where((e) => e.trim().isNotEmpty).toList(),
        'category': tags.isNotEmpty ? tags.first : field.name,
        'co_authors': authors
            .where((a) => !a.isCorresponding)
            .map((a) => a.institution.isEmpty ? a.name : '${a.name} - ${a.institution}')
            .toList(),
        'tag_ids': tagIds ?? catalogTags.map((t) => t['id'].toString()).toList(),
        'pdf_url': pdfUrl,
      };

  ResearchPaper copyWith({
    String? title,
    String? abstract,
    String? body,
    List<String>? keywords,
    String? references,
    List<ResearchAuthor>? authors,
    PaperStatus? status,
    ResearchField? field,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? publishedAt,
    bool? hasPdf,
    String? pdfUrl,
    int? views,
    int? downloads,
    int? bookmarks,
    List<ReviewComment>? reviewComments,
    List<PaperVersion>? versions,
    String? doi,
    String? journal,
    List<Map<String, dynamic>>? catalogTags,
  }) =>
      ResearchPaper(
        id: id,
        title: title ?? this.title,
        abstract: abstract ?? this.abstract,
        body: body ?? this.body,
        keywords: keywords ?? this.keywords,
        references: references ?? this.references,
        authors: authors ?? this.authors,
        status: status ?? this.status,
        field: field ?? this.field,
        tags: tags ?? this.tags,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        publishedAt: publishedAt ?? this.publishedAt,
        hasPdf: hasPdf ?? this.hasPdf,
        pdfUrl: pdfUrl ?? this.pdfUrl,
        views: views ?? this.views,
        downloads: downloads ?? this.downloads,
        bookmarks: bookmarks ?? this.bookmarks,
        reviewComments: reviewComments ?? this.reviewComments,
        versions: versions ?? this.versions,
        doi: doi ?? this.doi,
        journal: journal ?? this.journal,
        catalogTags: catalogTags ?? this.catalogTags,
      );
}
