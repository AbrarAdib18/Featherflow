# Farmer News / Research panel (Knowledge Portal)

The farmer app's "Knowledge Portal" (`lib/features/paper_portal/`) reads the
`articles` app. Articles are one table (`articles`) with `content_type`
discriminating research papers, news, market reports, innovation posts,
disease/feed studies, and Team FeatherFlow updates. Only `status='published'`
rows are ever returned to farmers.

## Seeding demo articles

```
backend/venv/Scripts/python.exe manage.py seed_news_demo          # create/refresh
backend/venv/Scripts/python.exe manage.py seed_news_demo --reset  # delete seeded rows first, then recreate
```

- **Idempotent.** Each article is matched by `(title, content_type)`. Re-running
  updates the existing rows in place — it never creates duplicates.
- Seeds 12 published articles across every `content_type`, authored by a demo
  user `news.desk@featherflow.example` (role `researcher`, password
  `FeatherflowDemo@2026`).
- Seeded rows carry `content_details.seed_marker = "ff-news-seed"`; `--reset`
  deletes exactly those.

### Adding more demo articles later

Append a tuple to the `ARTICLES` list in
[`articles/management/commands/seed_news_demo.py`](management/commands/seed_news_demo.py)
— `(title, content_type, category, source_type, keywords, is_featured,
days_ago, views, has_pdf, abstract, body)` — and re-run the command. Existing
rows are untouched; only the new one is created.

`content_type` must be one of: `research_paper`, `news`, `innovation`,
`disease_study`, `feed_study`, `market_report`, `team_update`.

## API shape

### List — `GET /api/articles/all/`

Public (auth optional; a signed-in farmer additionally gets `bookmarked`).
**Paginated. The list payload deliberately omits the full `body`** — fetch the
detail endpoint for that.

Query parameters:

| param | default | notes |
|---|---|---|
| `page` | `1` | 1-indexed |
| `page_size` | `20` | clamped to 1–50 |
| `type` | — | one `content_type`; this is how each portal tab fetches only its own data |
| `sort` | `latest` | `latest` \| `most_read` \| `trending` \| `most_bookmarked` |
| `search` | — | matches title / abstract / body (icontains) |
| `tag` | — | tag slug, category name, or keyword |
| `author` | — | author name or institution (icontains) |
| `year`, `year_from`, `year_to` | — | filter by `published_at` year |
| `featured` | — | `1`/`true` → featured only |

Response:

```json
{
  "results": [
    {
      "id": "uuid",
      "content_type": "news",
      "title": "…",
      "summary": "…",                 // abstract, trimmed to ~320 chars
      "category": "Best Practices",   // free-text label
      "source_type": "News",          // Research | News | Market | Innovation | Team FeatherFlow
      "image_url": "https://images.weserv.nl/?url=…",  // always set (per-type placeholder if none)
      "pdf_url": "https://… or null",
      "keywords": ["…"],              // max 6
      "read_minutes": 3,
      "views_count": 640,
      "bookmarks_count": 2,
      "bookmarked": false,            // per signed-in viewer
      "is_featured": true,
      "published_at": "2026-09-05T…",
      "created_at": "…",
      "updated_at": "…",
      "author": { "id": "uuid", "name": "…", "institution": "…", "is_verified": false }
    }
  ],
  "count": 15,
  "page": 1,
  "page_size": 20,
  "total_pages": 1,
  "has_next": false,
  "has_previous": false
}
```

Bookmark counts and the viewer's bookmark state are resolved in **two batch
queries for the whole page** (not per row). Page 1 is ~6 queries / <20 ms with
the demo data; it stays well under 300 ms as the table grows thanks to
`idx_articles_feed (status, content_type, published_at DESC)` and
`idx_bookmarks_target (target_type, target_id)` (see
`backend/postgres_backend_extension.sql`).

### Detail — `GET /api/articles/<content_type>/<id>/`

Public. Returns the **full** article including `body`, `tags`, `references`,
`farmer_summary`, `co_authors`, plus `image_url` / `source_type` / `read_minutes`.
Increments `views_count` by 1 per call.

### Report — `POST /api/articles/report/`

Auth required. Body `{ "content_id": "<uuid>", "reason": "…" }`. Creates a
`reports` row for the content-admin moderation queue.

## Known limitations

- **No full-text search index** — `search` is `ILIKE %term%` across title /
  abstract / body. Fine for the current corpus; revisit if the table grows past
  a few thousand rows.
- **No bookmarks list on this screen** — the bookmark toggle works, but the
  "my bookmarks" view lives in the researcher panel (`GET /api/research/bookmarks/`).
- **Placeholder images** — seeded articles use `images.weserv.nl`-proxied
  random photos (proxy adds the CORS headers Flutter web needs). Swap
  `content_details.image_url` for a real CDN URL per article any time.
- **Topic / author / year filters** in the app's filter sheet refine the
  currently loaded page client-side; tab, search and sort are server-side.
- The 4-second auto-refresh poll that previously re-fetched the entire feed was
  **removed** — it was the main cause of the lag. The screen now uses
  pull-to-refresh + infinite scroll (page-by-page).
