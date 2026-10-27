---
"better-supabase": minor
---

Add `blockTables(config)` to `better-supabase/sql`. It returns the memberships, membership roles and organizations tables with their configured schema, table and column names, plus every installed block's tables, so an authorization library's SQL follows the app's renames.
