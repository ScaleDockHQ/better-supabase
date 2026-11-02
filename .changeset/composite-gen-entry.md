---
"better-supabase": minor
---

`better-supabase gen` now writes a `blockConfig` entry for a composite block that has no SQL module
of its own once all of its parts are installed, and leaves it out while a part is missing. The
entry has the schema of its first part and no options. The "Composite blocks" page shows how to
build a composite next to its parts with `createBlocks`.
