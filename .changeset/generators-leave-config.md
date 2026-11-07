---
"better-supabase": minor
---

`better-supabase/config` no longer exports `zod`, `valibot`, `jsonSchema`, `toJsonSchema`, `standardSchema`, `factories` and `nuqs` or their option types. Import each from `better-supabase/generators/<name>`. Run `better-supabase codemod generators` to rewrite the imports; it also lists the lines of any generator that still uses the `apiVersion: 1` shape.
