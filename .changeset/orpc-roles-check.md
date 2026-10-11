---
"better-supabase": patch
---

`bs.authed()` in `better-supabase/orpc` now checks `roles` (and the new `permission` option) on their own. Before, it checked them only when `requireTenant` or `authorize` was also set, so a procedure guarded by `roles` alone let every signed-in caller through.
