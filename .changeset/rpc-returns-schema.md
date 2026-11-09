---
"better-supabase": minor
---

A function comment `@bsb returns=./file.ts#Schema` makes `db.$rpc` check the jsonb result with that Standard Schema. Zod and Valibot both work. A result that does not match throws.
