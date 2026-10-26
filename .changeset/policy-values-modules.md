---
"better-supabase": patch
---

Block modules now emit every row level security policy as a typed `Policy` value, so the installed SQL is laid out one clause per line. The policies, their names and their drops are unchanged, and a module that writes `create policy` by hand now fails the test suite.
