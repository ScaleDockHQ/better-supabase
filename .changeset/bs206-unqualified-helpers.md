---
"better-supabase": patch
---

Doctor BS206 now sees `col in (select f())` as a wrapped call when Postgres prints the helper without its schema, as it does for a function in `public`.
