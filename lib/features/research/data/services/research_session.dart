import 'package:flutter/foundation.dart';
import '../models/research_paper.dart';
import '../models/disease_update.dart';
import '../models/innovation_post.dart';
import '../models/researcher_profile.dart';
import '../research_demo_data.dart';

class ResearchSession extends ChangeNotifier {
  static final ResearchSession instance = ResearchSession._();
  ResearchSession._() {
    _papers = List.from(demoPapers);
    _diseaseUpdates = List.from(demoDiseaseUpdates);
    _innovations = List.from(demoInnovations);
  }

  late List<ResearchPaper> _papers;
  late List<DiseaseUpdate> _diseaseUpdates;
  late List<InnovationPost> _innovations;
  final Set<String> _bookmarkedPaperIds = {};

  ResearcherProfile get profile => demoResearcherProfile;
  List<ResearchPaper> get papers => List.unmodifiable(_papers);
  List<DiseaseUpdate> get diseaseUpdates =>
      List.unmodifiable(_diseaseUpdates);
  List<InnovationPost> get innovations =>
      List.unmodifiable(_innovations);

  List<ResearchPaper> get publishedPapers =>
      _papers.where((p) => p.status == PaperStatus.published).toList();

  List<ResearchPaper> papersByStatus(PaperStatus status) =>
      _papers.where((p) => p.status == status).toList();

  int get totalViews =>
      _papers.fold(0, (sum, p) => sum + p.views);

  int get totalDownloads =>
      _papers.fold(0, (sum, p) => sum + p.downloads);

  int get totalBookmarks =>
      _papers.fold(0, (sum, p) => sum + p.bookmarks);

  int get papersWithComments =>
      _papers.where((p) => p.reviewComments.isNotEmpty).length;

  void savePaper(ResearchPaper paper) {
    final idx = _papers.indexWhere((p) => p.id == paper.id);
    if (idx >= 0) {
      _papers[idx] = paper;
    } else {
      _papers.insert(0, paper);
    }
    notifyListeners();
  }

  void submitForReview(String paperId) {
    final idx = _papers.indexWhere((p) => p.id == paperId);
    if (idx < 0) return;
    _papers[idx] = _papers[idx].copyWith(
      status: PaperStatus.underReview,
      updatedAt: DateTime.now(),
      versions: [
        ..._papers[idx].versions,
        PaperVersion(
          versionNumber: _papers[idx].versions.length + 1,
          submittedAt: DateTime.now(),
          changeNotes: _papers[idx].versions.isEmpty
              ? 'Initial submission'
              : 'Resubmission',
        ),
      ],
    );
    notifyListeners();
  }

  void deletePaper(String paperId) {
    _papers.removeWhere((p) => p.id == paperId);
    notifyListeners();
  }

  void togglePaperBookmark(String paperId) {
    if (_bookmarkedPaperIds.contains(paperId)) {
      _bookmarkedPaperIds.remove(paperId);
    } else {
      _bookmarkedPaperIds.add(paperId);
    }
    notifyListeners();
  }

  bool isPaperBookmarked(String paperId) =>
      _bookmarkedPaperIds.contains(paperId);

  void resolveComment(String paperId, String commentId) {
    final idx = _papers.indexWhere((p) => p.id == paperId);
    if (idx < 0) return;
    final updated = _papers[idx].reviewComments
        .map((c) => c.id == commentId ? c.copyWith(resolved: true) : c)
        .toList();
    _papers[idx] = _papers[idx].copyWith(reviewComments: updated);
    notifyListeners();
  }

  ResearchPaper? findPaper(String id) {
    try {
      return _papers.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  List<ResearchPaper> searchPapers(String query) {
    final q = query.toLowerCase();
    return _papers
        .where((p) =>
            p.title.toLowerCase().contains(q) ||
            p.abstract.toLowerCase().contains(q) ||
            p.keywords.any((k) => k.toLowerCase().contains(q)) ||
            p.authors.any((a) => a.name.toLowerCase().contains(q)))
        .toList();
  }
}

extension ResearchSessionExt on ResearchSession {
  List<ResearchPaper> papersByStatusList(PaperStatus status) =>
      papers.where((p) => p.status == status).toList();
}
