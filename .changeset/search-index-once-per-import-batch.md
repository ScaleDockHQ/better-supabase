---
"better-supabase": minor
---

An import batch indexes each search record once. While `import_upsert_batch` runs, the search triggers note the records they touch and the batch indexes them when it ends, and a refresh that finds the same tenant, title, body, URL and description no longer rewrites the document. On a 1,000-row batch with an insert and a rename per row, `search_refresh` calls fall from 2,000 to 1,000 and the statement from 500 ms to 240 ms.

Watch triggers are plain `create trigger` statements instead of a `do` block, and `watch[].columns` limits the update trigger to named columns. `better-supabase upgrade` rewrites the `search` and `imports` modules and no data migration is needed. A watched table that is neither an app table nor a block table gets no trigger from the library, so create it in your own SQL.
