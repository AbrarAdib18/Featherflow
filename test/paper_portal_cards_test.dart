// Regression guard for the farmer Knowledge Portal cards.
//
// FeaturedArticleCard once used a `Row(crossAxisAlignment: stretch)` that threw
// "BoxConstraints forces an infinite height" inside a ListView and froze the
// whole app. These tests render both cards inside an unbounded-height ListView
// (exactly how the portal uses them) and assert the tree lays out clean.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:featherflow/features/paper_portal/models/article.dart';
import 'package:featherflow/features/paper_portal/widgets/article_card.dart';
import 'package:featherflow/features/paper_portal/widgets/featured_article_card.dart';

Article _fake({bool featured = false, ArticleCategory category = ArticleCategory.news}) {
  return Article(
    id: 'a1',
    title: 'New vaccine reduces Newcastle Disease mortality by 40%',
    summary: 'A multi-farm field trial recorded a 40% drop in flock mortality.',
    category: category,
    author: 'FeatherFlow Editorial Desk',
    authorRole: AuthorRole.official,
    source: 'FeatherFlow',
    date: DateTime(2026, 9, 1),
    readTimeMinutes: 3,
    isFeatured: featured,
    tags: const ['Research'],
    imageUrl: 'https://images.weserv.nl/?url=picsum.photos/seed/x/800/450',
    sourceType: 'Research',
  );
}

Future<void> _pumpInList(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: ListView(children: [child]),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  testWidgets('FeaturedArticleCard lays out in an unbounded ListView', (t) async {
    await _pumpInList(
      t,
      FeaturedArticleCard(article: _fake(featured: true), onTap: () {}),
    );
    expect(t.takeException(), isNull);
    expect(find.textContaining('Newcastle'), findsOneWidget);
    expect(find.text('Featured'), findsOneWidget);
  });

  testWidgets('ArticleCard lays out in an unbounded ListView', (t) async {
    await _pumpInList(t, ArticleCard(article: _fake(), onTap: () {}));
    expect(t.takeException(), isNull);
    expect(find.textContaining('Newcastle'), findsOneWidget);
  });

  testWidgets('ArticleCard renders for every category', (t) async {
    for (final category in ArticleCategory.values) {
      await _pumpInList(t, ArticleCard(article: _fake(category: category), onTap: () {}));
      expect(t.takeException(), isNull, reason: 'category $category threw');
    }
  });
}
