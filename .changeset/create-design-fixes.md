---
"better-supabase": patch
---

`encodeDesign` now throws a `DesignTooLongError` (still a `TypeError`, with the code's `length`) when a valid design is too long for a URL, so a caller can tell it apart from an invalid design. `better-supabase/preset` also exports `appReservedColumns(tenant)`, the columns every app table can get from its scope, and `isAppDefault(type, value)`, the default check `appTables` runs, so an editor can refuse a column name or a default before encoding.

Create uses them: a key to `auth.users` gets `owner_id` instead of the reserved `user_id` (which made the design fail to encode with a misleading "too large for a link" message), the Default field says which defaults a type takes, and changing a column's type drops a default the new type can't take. A table can now reference itself (`parent_id`, `on delete set null`) and reference the same table twice (`owner_id`, `assignee_id`, or `<table>_2_id`). Create also starts without blocks, from "Draw your own tables". `/create/prompt.md` takes `&design=<code>`, and the AI instructions link to it with the design.
