---
"better-supabase": minor
---

`vectorSearch` entries take `type: "halfvec"`, `hybrid` (full-text ranking fused with the vector ranking by reciprocal rank), `boost` (a score multiplier over the row) and `prefilter` columns that narrow before ranking. `db.$search` takes `filter`, `text` and `score: true`, which adds `$score` to each row from the new `search_<table>_scores` function the module writes for every entry. Run `better-supabase sql sync` to add it.
