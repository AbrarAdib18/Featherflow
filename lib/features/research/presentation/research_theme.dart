import 'package:flutter/material.dart';
import '../data/models/research_paper.dart';
import '../data/models/disease_update.dart';
import '../data/models/innovation_post.dart';

const double kResearchSidebarWidth = 240.0;
const double kResearchBreakpointWide = 900.0;

class RColors {
  RColors._();

  static const Color bg = Colors.white;
  static const Color appBar = Color(0xFF01291E);
  static const Color primary = Color(0xFF01291E);
  static const Color secondary = Color(0xFF1DB584);
  static const Color card = Colors.white;
  static const Color cardBorder = Color(0xFFE8E8E8);
  static const Color surface2 = Color(0xFFF5F5F5);
  static const Color divider = Color(0xFFEEEEEE);
  static const Color textPrimary = Color(0xFF1A1A1A);
  static const Color textSecondary = Color(0xFF666666);
  static const Color grey = Color(0xFF9E9E9E);
  static const Color verified = Color(0xFF1DB584);
  static const Color verifiedLight = Color(0xFFE8F5F0);

  // Paper status colors
  static const Color draft = Color(0xFF757575);
  static const Color draftLight = Color(0xFFF5F5F5);
  static const Color underReview = Color(0xFFF57C00);
  static const Color underReviewLight = Color(0xFFFFF3E0);
  static const Color needsRevision = Color(0xFFC62828);
  static const Color needsRevisionLight = Color(0xFFFFEBEE);
  static const Color accepted = Color(0xFF1565C0);
  static const Color acceptedLight = Color(0xFFE3F2FD);
  static const Color published = Color(0xFF2E7D32);
  static const Color publishedLight = Color(0xFFE8F5E9);

  // Disease severity colors
  static const Color critical = Color(0xFFB71C1C);
  static const Color criticalLight = Color(0xFFFFEBEE);
  static const Color high = Color(0xFFE65100);
  static const Color highLight = Color(0xFFFFF3E0);
  static const Color medium = Color(0xFFF9A825);
  static const Color mediumLight = Color(0xFFFFF8E1);
  static const Color low = Color(0xFF2E7D32);
  static const Color lowLight = Color(0xFFE8F5E9);

  // Innovation category colors
  static const Color feeding = Color(0xFF1B5E20);
  static const Color feedingLight = Color(0xFFE8F5E9);
  static const Color housing = Color(0xFF0D47A1);
  static const Color housingLight = Color(0xFFE3F2FD);
  static const Color diseaseCtrl = Color(0xFF880E4F);
  static const Color diseaseCtrlLight = Color(0xFFFCE4EC);
  static const Color automationC = Color(0xFF4527A0);
  static const Color automationCLight = Color(0xFFEDE7F6);
  static const Color genetics = Color(0xFF006064);
  static const Color geneticsLight = Color(0xFFE0F7FA);
  static const Color sustainability = Color(0xFF33691E);
  static const Color sustainabilityLight = Color(0xFFF1F8E9);
  static const Color welfareC = Color(0xFF4E342E);
  static const Color welfareCLight = Color(0xFFEFEBE9);
}

BoxDecoration rCard({double radius = 12, bool highlight = false}) =>
    BoxDecoration(
      color: RColors.card,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: highlight
            ? RColors.secondary.withValues(alpha: 0.45)
            : RColors.cardBorder,
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    );

Widget rChip(String label, Color bg, Color fg, {double fontSize = 11}) =>
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: bg.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fg,
          fontSize: fontSize,
          fontWeight: FontWeight.w600,
        ),
      ),
    );

(Color bg, Color fg, String label) paperStatusColors(PaperStatus status) =>
    switch (status) {
      PaperStatus.draft => (RColors.draftLight, RColors.draft, 'Draft'),
      PaperStatus.underReview =>
        (RColors.underReviewLight, RColors.underReview, 'Under Review'),
      PaperStatus.needsRevision =>
        (RColors.needsRevisionLight, RColors.needsRevision, 'Needs Revision'),
      PaperStatus.accepted =>
        (RColors.acceptedLight, RColors.accepted, 'Accepted'),
      PaperStatus.published =>
        (RColors.publishedLight, RColors.published, 'Published'),
    };

(Color bg, Color fg, String label) severityColors(DiseaseSeverity severity) =>
    switch (severity) {
      DiseaseSeverity.critical =>
        (RColors.criticalLight, RColors.critical, 'Critical'),
      DiseaseSeverity.high => (RColors.highLight, RColors.high, 'High'),
      DiseaseSeverity.medium =>
        (RColors.mediumLight, RColors.medium, 'Medium'),
      DiseaseSeverity.low => (RColors.lowLight, RColors.low, 'Low'),
    };

(Color bg, Color fg) innovationCategoryColors(InnovationCategory cat) =>
    switch (cat) {
      InnovationCategory.feeding => (RColors.feedingLight, RColors.feeding),
      InnovationCategory.housing => (RColors.housingLight, RColors.housing),
      InnovationCategory.diseaseControl =>
        (RColors.diseaseCtrlLight, RColors.diseaseCtrl),
      InnovationCategory.automation =>
        (RColors.automationCLight, RColors.automationC),
      InnovationCategory.genetics =>
        (RColors.geneticsLight, RColors.genetics),
      InnovationCategory.sustainability =>
        (RColors.sustainabilityLight, RColors.sustainability),
      InnovationCategory.welfare => (RColors.welfareCLight, RColors.welfareC),
    };

(Color bg, Color fg) researchFieldColors(dynamic field) {
  final idx = field.index as int;
  const pairs = [
    (Color(0xFFE8F5E9), Color(0xFF1B5E20)),
    (Color(0xFFFFEBEE), Color(0xFFB71C1C)),
    (Color(0xFFE3F2FD), Color(0xFF0D47A1)),
    (Color(0xFFFFF3E0), Color(0xFFE65100)),
    (Color(0xFFEDE7F6), Color(0xFF4527A0)),
    (Color(0xFFFCE4EC), Color(0xFF880E4F)),
    (Color(0xFFF1F8E9), Color(0xFF33691E)),
    (Color(0xFFE0F7FA), Color(0xFF006064)),
    (Color(0xFFFFF8E1), Color(0xFFF57C00)),
    (Color(0xFFE8EAF6), Color(0xFF283593)),
  ];
  return pairs[idx % pairs.length];
}
