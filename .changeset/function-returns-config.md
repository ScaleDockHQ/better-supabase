---
"better-supabase": minor
---

`gen.functions.<name>.returns` types the result of a function that returns `json` or `jsonb`: `{ schema: "./file.ts#name" }` takes a Standard Schema export and validates the result at runtime, `{ import: "./file.ts#Type" }` imports a type, and `{ type: "..." }` writes one. It does the same as the `@bsb returns` comment tag and wins over it.
