---
"better-supabase": minor
---

`importProject` in `better-supabase/create/lite` reads an existing project into a `Design` and a report. It takes a declarative schema or migrations folder (replayed in PGlite), any queryable database, or a Supabase project ref and access token (through the Management API read-only endpoint). The report lists what it modeled, what it kept as it is, the tables that belong to blocks, each table's adoption rung and the security findings. `catalogQuery` and `designFromCatalog` are exported for callers that run the query themselves.
