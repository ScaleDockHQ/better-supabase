---
"better-supabase": minor
---

The `extraColumns` option and its prefixed forms (`lineExtraColumns`, `categoryExtraColumns` and about 40 more) are removed from every block, and the Create design's `extraColumns` key is gone. A column your own schema file adds to a block's table is a field of the block; for a table you create yourself, list the columns in its comment as `@bsb fields plan, seats`. A config that still sets an option fails with a message that names `better-supabase codemod extra-columns`, which moves the columns into your files. It replaces `blocks.<name>.options.extraColumns`, `lineExtraColumns`, `calendarExtraColumns` and the other prefixed options. Doctor BS378 is removed, and fifteen blocks have no options schema any more.
