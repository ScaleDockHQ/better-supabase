---
"better-supabase": minor
---

`search`: a `config.records.<type>.search` entry takes `description` (returned on each hit as `SearchHit.description`), `exclude` (a column that keeps a row out of the index while it is set, separate from `deletedAt`), `from` (a view or table keyed by the record's id that the title, body, description and exclude columns read) and `watch` (related tables whose changes re-index the record, directly or through a `via` column). The index gains a `description` column only once a subject sets one, so existing configs render as before.
