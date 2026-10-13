---
"better-supabase": minor
---

Add the `versions` block (`better-supabase/blocks/versions` and the `versions` SQL module): numbered snapshots of any subject with a content hash, labels, debounced auto snapshots, versions frozen when a status column changes, retention, restore through columns or an apply function, and `diff()` as an RFC 6902 JSON Patch. `createPatch()` and `applyPatch()` are exported for any JSON value. The module records `version.created`, `version.restored` and `version.deleted`.
