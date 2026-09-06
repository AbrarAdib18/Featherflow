import 'research_paper.dart' show PaperStatus, paperStatusFromApi;

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
  final int version;
  final String? reviewNotes;
  final List<String> mediaUrls;
  final List<Map<String, dynamic>> catalogTags;

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
    this.version = 1,
    this.reviewNotes,
    this.mediaUrls = const [],
    this.catalogTags = const [],
  });

  factory InnovationPost.blank(String authorName) => InnovationPost(
        id: '', title: '', summary: '', details: '', sourceDetails: '',
        category: InnovationCategory.automation, authorId: '', authorName: authorName,
        publishedAt: DateTime.now(), status: PaperStatus.draft,
      );

  factory InnovationPost.fromJson(Map<String, dynamic> json) {
    final author = Map<String, dynamic>.from(json['author'] as Map? ?? {});
    final category = (json['category'] ?? '').toString().toLowerCase();
    return InnovationPost(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      summary: (json['summary'] ?? json['abstract'] ?? '').toString(),
      details: (json['description'] ?? json['body'] ?? '').toString(),
      sourceDetails: json['source_details']?.toString() ?? '',
      category: InnovationCategory.values.firstWhere(
        (c) => c.name.toLowerCase() == category,
        orElse: () => InnovationCategory.automation,
      ),
      authorId: author['id']?.toString() ?? '',
      authorName: author['name']?.toString() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      status: paperStatusFromApi(json['status']?.toString()),
      tags: List<String>.from(json['keywords'] as List? ?? []),
      views: (json['views_count'] as num?)?.toInt() ?? 0,
      bookmarks: (json['bookmarks_count'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
      reviewNotes: json['review_notes'] as String?,
      mediaUrls: List<String>.from(json['media_urls'] as List? ?? []),
      catalogTags: List<Map<String, dynamic>>.from(
          (json['tags'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
    );
  }

  Map<String, dynamic> toRequestJson({List<String>? tagIds}) => {
        'title': title,
        'summary': summary,
        'description': details,
        'source_details': sourceDetails,
        'category': category.name,
        'keywords': tags,
        'media_urls': mediaUrls,
        'tag_ids': tagIds ?? catalogTags.map((t) => t['id'].toString()).toList(),
      };
}
