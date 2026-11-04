---
"better-supabase": minor
---

`AuthorizationProvider` gains optional fields that fill config defaults: `functions.subject` (the bootstrap subject), role `through` with `tenant` and `where`, membership `disabledAt`, `platformRoles` and `personas`. `AuthorizationProvider<Key>` types the permission keys in `blocks.*.permissions`, `subjects.*.permissions` and role lists. `providerPersonaTests` writes one access matrix file per persona, and doctor BS426 reports config values that repeat the provider's.
