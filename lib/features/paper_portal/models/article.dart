import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/network/auth_service.dart';

enum ArticleCategory {
  researchPaper,
  news,
  innovation,
  diseaseStudy,
  feedStudy,
  marketReport,
  teamFeatherflow,
}

const _categoryToApi = {
  ArticleCategory.researchPaper: 'research_paper',
  ArticleCategory.news: 'news',
  ArticleCategory.innovation: 'innovation',
  ArticleCategory.diseaseStudy: 'disease_study',
  ArticleCategory.feedStudy: 'feed_study',
  ArticleCategory.marketReport: 'market_report',
  ArticleCategory.teamFeatherflow: 'team_update',
};

ArticleCategory articleCategoryFromApi(String? value) => _categoryToApi.entries
    .firstWhere((e) => e.value == value, orElse: () => _categoryToApi.entries.first)
    .key;

String articleCategoryToApi(ArticleCategory category) => _categoryToApi[category]!;

enum AuthorRole { researcher, official, team }

enum UserRole { admin, researcher, viewer }

/// Derived live from the signed-in user's roles — a researcher can create
/// articles, an admin (any admin_* role) can moderate, everyone else views.
UserRole get currentUserRole {
  final roles = AuthService.instance.currentSession?.user.roles ?? const [];
  final lower = roles.map((r) => r.toLowerCase());
  if (lower.any((r) => r.startsWith('admin'))) return UserRole.admin;
  if (lower.contains('researcher')) return UserRole.researcher;
  return UserRole.viewer;
}

enum SortOrder { latest, mostRead, mostCited, trending }

const _sortToApi = {
  SortOrder.latest: 'latest',
  SortOrder.mostRead: 'most_read',
  SortOrder.mostCited: 'most_bookmarked',
  SortOrder.trending: 'trending',
};

String sortOrderToApi(SortOrder sort) => _sortToApi[sort]!;

class Article {
  final String id;
  final String title;
  final String summary;
  final String? body;
  final ArticleCategory category;
  final String author;
  final AuthorRole authorRole;
  final String source;
  final DateTime date;
  final int readTimeMinutes;
  final bool isVerified;
  final bool isFeatured;
  final bool isTeamFeatherflow;
  final List<String> tags;
  final int viewsCount;
  final int bookmarksCount;
  final bool bookmarked;
  final List<String> references;
  final String? farmerSummary;
  final String? imageUrl;
  final String sourceType;

  const Article({
    required this.id,
    required this.title,
    required this.summary,
    this.body,
    required this.category,
    required this.author,
    required this.authorRole,
    required this.source,
    required this.date,
    required this.readTimeMinutes,
    this.isVerified = false,
    this.isFeatured = false,
    this.isTeamFeatherflow = false,
    this.tags = const [],
    this.viewsCount = 0,
    this.bookmarksCount = 0,
    this.bookmarked = false,
    this.references = const [],
    this.farmerSummary,
    this.imageUrl,
    this.sourceType = 'News',
  });

  factory Article.fromJson(Map<String, dynamic> json) {
    final author = Map<String, dynamic>.from(json['author'] as Map? ?? {});
    final category = articleCategoryFromApi(json['content_type']?.toString());
    final body = json['body']?.toString();
    final serverMinutes = (json['read_minutes'] as num?)?.toInt();
    final wordCount = (body ?? '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty).length;
    final imageUrl = json['image_url']?.toString();
    return Article(
      id: json['id'].toString(),
      title: json['title']?.toString() ?? '',
      summary: json['summary']?.toString() ?? '',
      body: body,
      category: category,
      author: author['name']?.toString() ?? 'Unknown',
      authorRole: category == ArticleCategory.teamFeatherflow
          ? AuthorRole.team
          : (author['is_verified'] == true ? AuthorRole.researcher : AuthorRole.official),
      source: author['institution']?.toString().isNotEmpty == true
          ? author['institution'].toString()
          : 'Featherflow',
      date: DateTime.tryParse(json['published_at']?.toString() ?? '') ??
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      readTimeMinutes: serverMinutes != null && serverMinutes > 0
          ? serverMinutes.clamp(1, 60)
          : (wordCount / 200).ceil().clamp(1, 60),
      isVerified: author['is_verified'] == true,
      isFeatured: json['is_featured'] == true,
      isTeamFeatherflow: category == ArticleCategory.teamFeatherflow,
      tags: [
        if ((json['category'] ?? '').toString().isNotEmpty) json['category'].toString(),
        ...List<String>.from(json['keywords'] as List? ?? []),
      ],
      viewsCount: (json['views_count'] as num?)?.toInt() ?? 0,
      bookmarksCount: (json['bookmarks_count'] as num?)?.toInt() ?? 0,
      bookmarked: json['bookmarked'] == true,
      references: List<String>.from(json['references'] as List? ?? []),
      farmerSummary: (json['farmer_summary'] as String?)?.trim().isNotEmpty == true
          ? json['farmer_summary'] as String
          : null,
      imageUrl: imageUrl != null && imageUrl.isNotEmpty ? imageUrl : null,
      sourceType: json['source_type']?.toString() ?? 'News',
    );
  }
}

class PPColors {
  PPColors._();

  static const primary = Color(0xFF2D6A4F);
  static const accent = Color(0xFF52B788);
  static const lightSurface = Color(0xFFE8F5EE);
  static const amber = Color(0xFFF9A825);
  static const bg = Color(0xFFFFFFFF);
  static const surface2 = Color(0xFFF7F9F8);
  static const textPrimary = Color(0xFF1A1A1A);
  static const textSecondary = Color(0xFF6B7280);
  static const border = Color(0xFFE5E7EB);
  static const amberBg = Color(0xFFFFF8E1);
  static const amberText = Color(0xFF7B6000);

  static const researchBg = Color(0xFFE8F5EE);
  static const researchText = Color(0xFF2D6A4F);
  static const newsBg = Color(0xFFE3F2FD);
  static const newsText = Color(0xFF1565C0);
  static const innovationBg = Color(0xFFF3EEF9);
  static const innovationText = Color(0xFF6B3FA0);
  static const diseaseBg = Color(0xFFFFF8E1);
  static const diseaseText = Color(0xFF7B6000);
  static const feedBg = Color(0xFFE0F2F1);
  static const feedText = Color(0xFF00695C);
  static const marketBg = Color(0xFFFDECEA);
  static const marketText = Color(0xFFC0392B);
}

String ppTimeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inDays >= 365) return '${(diff.inDays / 365).floor()}y ago';
  if (diff.inDays >= 30) return '${(diff.inDays / 30).floor()}mo ago';
  if (diff.inDays >= 1) return '${diff.inDays}d ago';
  if (diff.inHours >= 1) return '${diff.inHours}h ago';
  return '${diff.inMinutes}m ago';
}

String ppFormatDate(DateTime date) {
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}

TextStyle ppTitle({double size = 15, Color? color}) => GoogleFonts.merriweather(
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color ?? PPColors.textPrimary,
      height: 1.4,
    );

TextStyle ppBody({double size = 13, Color? color}) => GoogleFonts.lato(
      fontSize: size,
      color: color ?? PPColors.textSecondary,
      height: 1.6,
    );

TextStyle ppLabel({
  double size = 12,
  FontWeight weight = FontWeight.w500,
  Color? color,
}) =>
    GoogleFonts.lato(
      fontSize: size,
      fontWeight: weight,
      color: color ?? PPColors.textSecondary,
    );

BoxDecoration ppCardDecoration() => BoxDecoration(
      color: PPColors.bg,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: PPColors.border, width: 0.5),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    );

LinearGradient ppCategoryGradient(ArticleCategory cat) {
  switch (cat) {
    case ArticleCategory.researchPaper:
      return const LinearGradient(
        colors: [Color(0xFF1B4332), Color(0xFF2D6A4F), Color(0xFF52B788)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.diseaseStudy:
      return const LinearGradient(
        colors: [Color(0xFF5C4100), Color(0xFF7B6000), Color(0xFFF9A825)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.news:
      return const LinearGradient(
        colors: [Color(0xFF0A2E6A), Color(0xFF1565C0), Color(0xFF42A5F5)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.innovation:
      return const LinearGradient(
        colors: [Color(0xFF3A1F5C), Color(0xFF6B3FA0), Color(0xFFAB47BC)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.feedStudy:
      return const LinearGradient(
        colors: [Color(0xFF004D40), Color(0xFF00695C), Color(0xFF26A69A)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.marketReport:
      return const LinearGradient(
        colors: [Color(0xFF7F0000), Color(0xFFC0392B), Color(0xFFE57373)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
    case ArticleCategory.teamFeatherflow:
      return const LinearGradient(
        colors: [Color(0xFF1B4332), Color(0xFF2D6A4F), Color(0xFFF9A825)],
        begin: Alignment.topLeft, end: Alignment.bottomRight,
      );
  }
}
