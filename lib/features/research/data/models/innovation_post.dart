import 'research_paper.dart' show PaperStatus;

enum InnovationCategory {
  feeding,
  housing,
  diseaseControl,
  automation,
  genetics,
  sustainability,
  welfare,
}

extension InnovationCategoryLabel on InnovationCategory {
  String get label => switch (this) {
        InnovationCategory.feeding => 'Feeding',
        InnovationCategory.housing => 'Housing',
        InnovationCategory.diseaseControl => 'Disease Control',
        InnovationCategory.automation => 'Automation',
        InnovationCategory.genetics => 'Genetics',
        InnovationCategory.sustainability => 'Sustainability',
        InnovationCategory.welfare => 'Welfare',
      };
}

class InnovationPost {
  final String id;
  final String title;
  final String summary;
  final String details;
  final String sourceDetails;
  final InnovationCategory category;
  final String authorId;
  final String authorName;
  final DateTime publishedAt;
  final PaperStatus status;
  final List<String> tags;
  final int views;
  final int bookmarks;

  const InnovationPost({
    required this.id,
    required this.title,
    required this.summary,
    required this.details,
    required this.sourceDetails,
    required this.category,
    required this.authorId,
    required this.authorName,
    required this.publishedAt,
    this.status = PaperStatus.published,
    this.tags = const [],
    this.views = 0,
    this.bookmarks = 0,
  });
}
