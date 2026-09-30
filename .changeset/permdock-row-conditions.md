---
'better-supabase': patch
---

Document that the `permdock` policy mode for buckets and topics only fits permissions whose grants have no row conditions beyond the scope. PermDock's helpers check role and scope, so a permission with row conditions (for example `ownerId = principal.id`) would grant every object in the scope. Leave those to the policies `permdock rls generate` writes. The storage, realtime and PermDock docs pages show a wrong and a right example, and the TSDoc on the `policy` and `permdock` options says the same.
