---
"better-supabase": patch
---

Doctor BS214 compares a Storage or Realtime policy's scope with the tenancy scopes PermDock's catalog grants the permission at (`grants[].scope`), instead of the permission entry's `scope`, which current catalogs fill with the OAuth scope (`chat:read`) and which gave false errors. Catalogs without `grants` still use the entry's `scope` when it names a tenancy scope. `PermdockCatalog` gains `grants` and `scopes`.
