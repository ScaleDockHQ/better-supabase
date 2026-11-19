---
"better-supabase": patch
---

Doctor false positives from an adopter:

- BS112 counts a call to the access contract (`better_supabase.can`, `can_user`, `is_platform`, `tenant_ids_with`) or to a function in a schema of the authorization provider's functions as a caller check.
- BS633 skips row triggers whose function lives in a schema of the authorization provider's functions; they guard the provider's own rows and must run during an import.
- BS634 and BS635 no longer suggest an `include` through a view, whose generated table has no `relations`.
- BS627 reads a raise's whole `using` list, so a hint on the fourth or later line counts.
