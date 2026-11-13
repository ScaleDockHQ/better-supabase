---
"better-supabase": minor
---

The `legal-entities`, `courses` and `content` blocks page, facet and count through the shared list implementation (ADR 0749, 0789). `legal_entity`, `course` and `content_entry` declare `sorts`, `facets` and `filters` in their manifests, and each client gains `page`, `facets` and `count`. The SQL functions `list_legal_entities`, `list_courses` and `list_content_entries` now take `(tenant, filters jsonb)`. `content.list` reads its text search from `query` as before and sends it as `filters.search`; `legalEntities.list` and `courses.list` are capped at 500 rows (200 by default). An unknown `status` on a course list now matches no rows instead of raising `COURSE_INVALID`. The `sso` block keeps its SCIM `startIndex` and `count` paging and its bounded `domains()` and `providers()` lists. Apply the generated migration to adopt the new list functions.

| Before                                                         | After                                                                       |
| -------------------------------------------------------------- | --------------------------------------------------------------------------- |
| `list_legal_entities(tenant, include_archived)`                | `list_legal_entities(tenant, filters)` with `filters.includeArchived`       |
| `list_courses(tenant, status)`                                 | `list_courses(tenant, filters)` with `filters.status`                       |
| `list_content_entries(tenant, filter)`                         | `list_content_entries(tenant, filters)`                                     |
| `content.list({ query })` was the only text search             | `content.page({ q })` matches the title and slug                            |
| `courses.list()` and `legalEntities.list()` returned every row | A capped list; use `page` past 500 rows                                     |
| No facet counts or sort choice for these three lists           | `facets()`, `count()` and `sort: { by }` from the entity's declared `sorts` |
