---
"better-supabase": minor
---

Relation kinds can name the subject types each end accepts, and other blocks can contribute kinds.

- `blocks.relations.options.kinds.<kind>.types` takes `{ source, target }`, lists of subject types in the stored direction. `link` refuses other types with the hint `RELATION_TYPE_NOT_ALLOWED` (sqlstate `22023`); a symmetric kind accepts either order. The `kinds` option is now typed in the config.
- Blocks contribute kinds to `relations` through `contributes.relations`. A contributed kind is added next to the app's kinds, and an app kind with the same name replaces it.
