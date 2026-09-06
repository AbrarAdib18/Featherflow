import 'dart:async';
import 'package:flutter/foundation.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../core/network/user_updates_service.dart';
import '../models/research_paper.dart';
import '../models/disease_update.dart';
import '../models/innovation_post.dart';
import '../models/researcher_profile.dart';
import 'research_api_service.dart';

const _emptyProfile = ResearcherProfile(
  id: '', name: '', email: '', institution: '', department: '',
  researchInterests: [], bio: '', isVerified: false, contactEmail: '',
);

class ResearchSession extends ChangeNotifier {
  static final ResearchSession instance = ResearchSession._();
  ResearchSession._() {
    AuthService.instance.addListener(_onAuthChanged);
    // Real-time: an admin action detected by the shared /me/updates poll also
    // pokes this session so a verify / publish decision lands promptly.
    UserUpdatesService.instance.addRefreshHook(() {
      if (_isResearcher) refresh(silent: true);
    });
    _onAuthChanged();
  }

  List<ResearchPaper> _papers = [];
  List<DiseaseUpdate> _diseaseUpdates = [];
  List<InnovationPost> _innovations = [];
  final Set<String> _bookmarkedArticleIds = {};
  ResearcherProfile _profile = _emptyProfile;
  bool isLoading = false;
  String? errorMessage;
  Timer? _pollTimer;
  bool _isResearcher = false;

  Future<void> _onAuthChanged() async {
    final session = AuthService.instance.currentSession ??
        await AuthService.instance.getStoredSession();
    if (session == null) {
      _pollTimer?.cancel();
      _isResearcher = false;
      return;
    }
    _isResearcher = session.user.roles.any((role) => role.toLowerCase() == 'researcher');
    if (!_isResearcher) return;
    await refresh();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) => refresh(silent: true));
  }

  Future<void> refresh({bool silent = false}) async {
    if (!_isResearcher || isLoading) return;
    isLoading = true;
    errorMessage = null;
    if (!silent) notifyListeners();
    try {
      final api = ResearchApiService.instance;
      final results = await Future.wait([
        api.profile(),
        api.list('papers'),
        api.list('disease-updates'),
        api.list('innovations'),
        api.bookmarks(),
      ]);
      _profile = ResearcherProfile.fromJson(results[0] as Map<String, dynamic>);
      _papers = (results[1] as List<Map<String, dynamic>>)
          .map(ResearchPaper.fromJson)
          .toList();
      _diseaseUpdates = (results[2] as List<Map<String, dynamic>>)
          .map(DiseaseUpdate.fromJson)
          .toList();
      _innovations = (results[3] as List<Map<String, dynamic>>)
          .map(InnovationPost.fromJson)
          .toList();
      _bookmarkedArticleIds
        ..clear()
        ..addAll((results[4] as List<Map<String, dynamic>>).map((e) => e['id'].toString()));
    } catch (error) {
      errorMessage = error.toString();
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  ResearcherProfile get profile => _profile;
  List<ResearchPaper> get papers => List.unmodifiable(_papers);
  List<DiseaseUpdate> get diseaseUpdates => List.unmodifiable(_diseaseUpdates);
  List<InnovationPost> get innovations => List.unmodifiable(_innovations);

  List<ResearchPaper> get publishedPapers =>
      _papers.where((p) => p.status == PaperStatus.published).toList();

  List<ResearchPaper> papersByStatus(PaperStatus status) =>
      _papers.where((p) => p.status == status).toList();

  int get totalViews => _papers.fold(0, (sum, p) => sum + p.views);

  int get totalDownloads => _papers.fold(0, (sum, p) => sum + p.downloads);

  int get totalBookmarks => _papers.fold(0, (sum, p) => sum + p.bookmarks);

  int get papersWithComments =>
      _papers.where((p) => p.reviewComments.isNotEmpty).length;

  Future<void> updateProfile(ResearcherProfile updated, {bool fullUpdate = false}) async {
    final result = await ResearchApiService.instance
        .updateProfile(fullUpdate ? updated.toFullUpdateJson() : updated.toUpdateJson());
    _profile = ResearcherProfile.fromJson(result);
    notifyListeners();
  }

  /// Creates or updates a paper depending on whether its id is already
  /// known locally, then submits it for review if the caller set its status
  /// to underReview (matching the pre-existing new_paper_screen contract —
  /// the backend requires a separate submit-review call after save).
  Future<void> savePaper(ResearchPaper paper) async {
    final isNew = !_papers.any((p) => p.id == paper.id);
    final submit = paper.status == PaperStatus.underReview;
    final result = isNew
        ? await ResearchApiService.instance.create('papers', paper.toRequestJson())
        : await ResearchApiService.instance.update('papers', paper.id, paper.toRequestJson());
    var saved = ResearchPaper.fromJson(result);
    if (submit) {
      final submitted = await ResearchApiService.instance.submitForReview('papers', saved.id);
      saved = ResearchPaper.fromJson(submitted);
    }
    final idx = _papers.indexWhere((p) => p.id == paper.id);
    if (idx >= 0) {
      _papers[idx] = saved;
    } else {
      _papers.insert(0, saved);
    }
    notifyListeners();
  }

  Future<void> submitForReview(String paperId) async {
    final result = await ResearchApiService.instance.submitForReview('papers', paperId);
    final saved = ResearchPaper.fromJson(result);
    final idx = _papers.indexWhere((p) => p.id == paperId);
    if (idx >= 0) _papers[idx] = saved;
    notifyListeners();
  }

  Future<void> deletePaper(String paperId) async {
    await ResearchApiService.instance.delete('papers', paperId);
    _papers.removeWhere((p) => p.id == paperId);
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> paperVersions(String paperId) =>
      ResearchApiService.instance.versionHistory('papers', paperId);

  Future<void> saveDiseaseUpdate(DiseaseUpdate update, {required bool submit}) async {
    final isNew = update.id.isEmpty;
    final result = isNew
        ? await ResearchApiService.instance.create('disease-updates', update.toRequestJson())
        : await ResearchApiService.instance.update('disease-updates', update.id, update.toRequestJson());
    var saved = DiseaseUpdate.fromJson(result);
    if (submit) {
      final submitted = await ResearchApiService.instance.submitForReview('disease-updates', saved.id);
      saved = DiseaseUpdate.fromJson(submitted);
    }
    final idx = _diseaseUpdates.indexWhere((d) => d.id == update.id);
    if (idx >= 0) {
      _diseaseUpdates[idx] = saved;
    } else {
      _diseaseUpdates.insert(0, saved);
    }
    notifyListeners();
  }

  Future<void> deleteDiseaseUpdate(String id) async {
    await ResearchApiService.instance.delete('disease-updates', id);
    _diseaseUpdates.removeWhere((d) => d.id == id);
    notifyListeners();
  }

  DiseaseUpdate? findDiseaseUpdate(String id) {
    try {
      return _diseaseUpdates.firstWhere((d) => d.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveInnovation(InnovationPost post, {required bool submit}) async {
    final isNew = post.id.isEmpty;
    final result = isNew
        ? await ResearchApiService.instance.create('innovations', post.toRequestJson())
        : await ResearchApiService.instance.update('innovations', post.id, post.toRequestJson());
    var saved = InnovationPost.fromJson(result);
    if (submit) {
      final submitted = await ResearchApiService.instance.submitForReview('innovations', saved.id);
      saved = InnovationPost.fromJson(submitted);
    }
    final idx = _innovations.indexWhere((i) => i.id == post.id);
    if (idx >= 0) {
      _innovations[idx] = saved;
    } else {
      _innovations.insert(0, saved);
    }
    notifyListeners();
  }

  Future<void> deleteInnovation(String id) async {
    await ResearchApiService.instance.delete('innovations', id);
    _innovations.removeWhere((i) => i.id == id);
    notifyListeners();
  }

  InnovationPost? findInnovation(String id) {
    try {
      return _innovations.firstWhere((i) => i.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> toggleArticleBookmark(String articleId) async {
    final bookmarked = await ResearchApiService.instance.toggleBookmark(articleId);
    if (bookmarked) {
      _bookmarkedArticleIds.add(articleId);
    } else {
      _bookmarkedArticleIds.remove(articleId);
    }
    notifyListeners();
  }

  /// Kept for backward compatibility with screens written against the old
  /// in-memory session — bookmarking now targets a published article id
  /// (a paper's own id doubles as its article id in the unified backend).
  void togglePaperBookmark(String paperId) => toggleArticleBookmark(paperId);

  bool isPaperBookmarked(String paperId) => _bookmarkedArticleIds.contains(paperId);

  /// Review comments/editor notes are surfaced read-only from the admin's
  /// review_notes field (Pass 1) — resolving them is a Pass 2 feature once
  /// a real reviewer-comment thread exists on the backend.
  void resolveComment(String paperId, String commentId) {}

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
