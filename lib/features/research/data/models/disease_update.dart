import 'research_paper.dart' show PaperStatus;

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
  });
}
