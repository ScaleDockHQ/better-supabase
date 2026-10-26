---
"better-supabase": minor
---

`better-supabase/create/lite` adds `verifyFiles`, `verifyCatalog`, `verifyQuery`, `readSecurityCatalog` and `accessMatrix`. They check row level security, write policies that are only `true`, `anon` and `PUBLIC` grants and `search_path` on security definer functions, and report how far `anon` and `authenticated` reach per table and command (ADR 0105).
