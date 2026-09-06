import 'research_paper.dart' show PaperStatus, paperStatusFromApi;

enum DiseaseSeverity { low, medium, high, critical }

extension DiseaseSeverityLabel on DiseaseSeverity {
  String get label => switch (this) {
        DiseaseSeverity.low => 'Low',
        DiseaseSeverity.medium => 'Medium',
        DiseaseSeverity.high => 'High',
        DiseaseSeverity.critical => 'Critical',
      };
}

class DiseaseUpdate {
  final String id;
  final String diseaseName;
  final String causativeAgent;
  final String symptoms;
  final String treatments;
  final String preventionMethods;
  final String farmerSummary;
  final String authorId;
  final String authorName;
  final DateTime publishedAt;
  final PaperStatus status;
  final List<String> affectedBreeds;
  final DiseaseSeverity severity;
  final int views;
  final int bookmarks;
  final int version;
  final String? reviewNotes;
  final List<Map<String, dynamic>> catalogTags;

  const DiseaseUpdate({
    required this.id,
    required this.diseaseName,
    required this.causativeAgent,
    required this.symptoms,
    required this.treatments,
    required this.preventionMethods,
    required this.farmerSummary,
    required this.authorId,
    required this.authorName,
    required this.publishedAt,
    required this.severity,
    this.status = PaperStatus.published,
    this.affectedBreeds = const [],
    this.views = 0,
    this.bookmarks = 0,
    this.version = 1,
    this.reviewNotes,
    this.catalogTags = const [],
  });

  factory DiseaseUpdate.blank(String authorName) => DiseaseUpdate(
        id: '', diseaseName: '', causativeAgent: '', symptoms: '', treatments: '',
        preventionMethods: '', farmerSummary: '', authorId: '', authorName: authorName,
        publishedAt: DateTime.now(), severity: DiseaseSeverity.medium, status: PaperStatus.draft,
      );

  factory DiseaseUpdate.fromJson(Map<String, dynamic> json) {
    final author = Map<String, dynamic>.from(json['author'] as Map? ?? {});
    return DiseaseUpdate(
      id: json['id'].toString(),
      diseaseName: (json['disease_name'] ?? json['title'] ?? '').toString(),
      causativeAgent: '',
      symptoms: json['symptoms']?.toString() ?? '',
      treatments: json['treatment']?.toString() ?? '',
      preventionMethods: json['prevention']?.toString() ?? '',
      farmerSummary: (json['practical_summary'] ?? json['farmer_summary'] ?? '').toString(),
      authorId: author['id']?.toString() ?? '',
      authorName: author['name']?.toString() ?? '',
      publishedAt: DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      status: paperStatusFromApi(json['status']?.toString()),
      affectedBreeds: const [],
      severity: DiseaseSeverity.medium,
      views: (json['views_count'] as num?)?.toInt() ?? 0,
      bookmarks: (json['bookmarks_count'] as num?)?.toInt() ?? 0,
      version: (json['version'] as num?)?.toInt() ?? 1,
      reviewNotes: json['review_notes'] as String?,
      catalogTags: List<Map<String, dynamic>>.from(
          (json['tags'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map))),
    );
  }

  Map<String, dynamic> toRequestJson({List<String>? tagIds}) => {
        'title': diseaseName,
        'symptoms': symptoms,
        'treatment': treatments,
        'prevention': preventionMethods,
        'farmer_summary': farmerSummary,
        'tag_ids': tagIds ?? catalogTags.map((t) => t['id'].toString()).toList(),
      };
}
