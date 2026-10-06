---
"better-supabase": patch
---

Text columns, and json `path` filters, take `match` and `imatch`: a POSIX regular expression, case-sensitive (`~`) or not (`~*`). They compile to PostgREST's `match` and `imatch` operators and to `~` and `~*` over SQL. SQLite returns `unsupported`.
