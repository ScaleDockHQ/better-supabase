---
"better-supabase": patch
---

`doctor` no longer reports BS610 when a `"use cache: private"` function calls a method that has the name of another private function, such as `db.tills.getSession(id)` next to a `getSession` helper.
