---
"better-supabase": minor
---

`createNext` takes `heldPermissions`, a function that returns the caller's keys without a database call. Record loaders and `recordListServer` read their `can` flags from it and call `my_permissions` only when it returns `null`.
