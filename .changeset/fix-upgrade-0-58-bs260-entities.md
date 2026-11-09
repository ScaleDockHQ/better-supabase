---
"better-supabase": minor
---

Doctor BS260 no longer reports `workItemId` or `workItemIds` for an app that renamed the entity through `blocks.<name>.entities` (or `names`), such as `work_item`: the verb arguments follow the entity name there, so they are not the old ones. `codemod naming` still renames them in an app that keeps the default names.
