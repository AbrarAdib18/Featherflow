enum PaperStatus { draft, underReview, needsRevision, accepted, published }

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
  final int views;
  final int downloads;
  final int bookmarks;
  final List<ReviewComment> reviewComments;
  final List<PaperVersion> versions;
  final String? doi;
  final String? journal;

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
    this.views = 0,
    this.downloads = 0,
    this.bookmarks = 0,
    this.reviewComments = const [],
    this.versions = const [],
    this.doi,
    this.journal,
  });

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
    int? views,
    int? downloads,
    int? bookmarks,
    List<ReviewComment>? reviewComments,
    List<PaperVersion>? versions,
    String? doi,
    String? journal,
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
        views: views ?? this.views,
        downloads: downloads ?? this.downloads,
        bookmarks: bookmarks ?? this.bookmarks,
        reviewComments: reviewComments ?? this.reviewComments,
        versions: versions ?? this.versions,
        doi: doi ?? this.doi,
        journal: journal ?? this.journal,
      );
}
