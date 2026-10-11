---
"better-supabase": minor
---

Add the `standardSchema()` generator. It writes `<output>.standard.ts` with a Standard Schema per table for its Row, Insert and Update shapes, built on the new `tableSchema()` runtime helper, so apps can validate writes without installing zod or valibot. Each schema also implements Standard JSON Schema for the `draft-2020-12`, `draft-07` and `openapi-3.0` targets, and the file exports `validators` for the validation plugin. `gen --metadata --emit standard-schema` prints it. Generators now receive `runtimeImport` in their input.
