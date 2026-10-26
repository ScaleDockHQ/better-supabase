---
"better-supabase": patch
---

`blocks.share-links.tables.views` and `tables.state` can be `null` when the block manages its own tables too; before, only a block over the app's tables could leave them out.
