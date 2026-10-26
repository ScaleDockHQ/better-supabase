---
"better-supabase": minor
---

`better-supabase/create/lite` adds `openSandbox` and `designDataApi`. `openSandbox(project)` applies a project's files to an in-memory PGlite database and offers `as({ sub, role, claims })` personas that run with row level security, plus a `rest(request)` handler for a subset of PostgREST (table reads and writes, filters, order, limit, offset, `rpc`). `designDataApi(preset, design)` returns the OpenAPI 3.1 document of the Data API a design produces. `validateDesign` now shares its file runner with the sandbox.
