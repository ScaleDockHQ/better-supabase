---
"better-supabase": patch
---

`doctor` matches a provider call the way Postgres stores it. BS428 and the table share check read `pg_policies.qual`, where a key literal carries a cast (`'tasks.read'::text`), the function may lose its schema or be quoted, and a key list is `ARRAY['a'::text, 'b'::text]` or `'{a,b}'::text[]`. All of those now count as the keys the policy checks. BS430 already read the function body as a parsed tree and handled casts, and BS429 reads no key literals.
