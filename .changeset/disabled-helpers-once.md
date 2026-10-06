---
"better-supabase": patch
---

`tenant_disabled` and `user_disabled` are defined in one module file: the `access` module's whenever it is installed outside custom mode, and the `tenant` module's only without it. The tenant file defers its function bodies while the access file defines them. The checks themselves, including the defaults from PermDock's `rls.suspension`, are unchanged.
