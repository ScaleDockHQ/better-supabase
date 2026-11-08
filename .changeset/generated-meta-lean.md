---
"better-supabase": minor
---

`better-supabase gen` writes `nullable` and `hasDefault` into `generated.meta.js` only for the columns where they are true, and leaves the `@bsb` tag block out of a table or column description. `ColumnMeta.nullable` and `ColumnMeta.hasDefault` are optional in the type, and an absent value means `false`. The metadata of a page's bundle shrinks and the OpenAPI documents stop showing the tags as text. Run `better-supabase gen` to rewrite the file.
