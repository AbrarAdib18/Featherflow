import 'package:flutter/material.dart';
import '../models/article.dart';

class CategoryBadge extends StatelessWidget {
  final ArticleCategory category;

  const CategoryBadge({super.key, required this.category});

  String get _label {
    switch (category) {
      case ArticleCategory.researchPaper:
        return 'Research Paper';
      case ArticleCategory.news:
        return 'News';
      case ArticleCategory.innovation:
        return 'Innovation';
      case ArticleCategory.diseaseStudy:
        return 'Disease Study';
      case ArticleCategory.feedStudy:
        return 'Feed Study';
      case ArticleCategory.marketReport:
        return 'Market Report';
      case ArticleCategory.teamFeatherflow:
        return 'Team Featherflow';
    }
  }

  Color get _bg {
    switch (category) {
      case ArticleCategory.researchPaper:
        return PPColors.researchBg;
      case ArticleCategory.news:
        return PPColors.newsBg;
      case ArticleCategory.innovation:
        return PPColors.innovationBg;
      case ArticleCategory.diseaseStudy:
        return PPColors.diseaseBg;
      case ArticleCategory.feedStudy:
        return PPColors.feedBg;
      case ArticleCategory.marketReport:
        return PPColors.marketBg;
      case ArticleCategory.teamFeatherflow:
        return PPColors.primary;
    }
  }

  Color get _text {
    switch (category) {
      case ArticleCategory.researchPaper:
        return PPColors.researchText;
      case ArticleCategory.news:
        return PPColors.newsText;
      case ArticleCategory.innovation:
        return PPColors.innovationText;
      case ArticleCategory.diseaseStudy:
        return PPColors.diseaseText;
      case ArticleCategory.feedStudy:
        return PPColors.feedText;
      case ArticleCategory.marketReport:
        return PPColors.marketText;
      case ArticleCategory.teamFeatherflow:
        return Colors.white;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        _label,
        style: ppLabel(
          size: 11,
          weight: FontWeight.w600,
          color: _text,
        ),
      ),
    );
  }
}
