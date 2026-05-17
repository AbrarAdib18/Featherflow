import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ArticleCategory {
  researchPaper,
  news,
  innovation,
  diseaseStudy,
  feedStudy,
  marketReport,
  teamFeatherflow,
}

enum AuthorRole { researcher, official, team }

enum UserRole { admin, researcher, viewer }

enum SortOrder { latest, mostRead, mostCited, trending }

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
  });
}

const UserRole currentUserRole = UserRole.researcher;

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
