---
"better-supabase": minor
---

Search can browse and page. A record type's `search.facets` lists columns that the index keeps in a new `facets` jsonb column (GIN `jsonb_path_ops`), and `search_documents` gets a `sort_key` column with a btree index for browsing. The new `search_page(q, types, tenant, filter, after, page_size)` function, and `Search.page`, return `{ items, nextCursor }`: without `q` it browses by title, with `q` it ranks like `search` over at most 500 candidates, and `filter` keeps documents whose facets contain it. `search` is unchanged. Run `better-supabase upgrade` and `db diff`; the module's data file reindexes existing documents.
