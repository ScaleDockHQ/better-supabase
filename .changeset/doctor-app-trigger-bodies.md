---
"better-supabase": minor
---

`better-supabase doctor` reads the bodies of your own triggers for the same-tenant check. BS340 no longer lists a foreign key column that an app trigger reads or writes, matching what `sameTenant.auto` leaves to the app, and the new BS398 warns when that trigger never mentions the tenant column, so the generated check is off and nothing replaces it. `better-supabase upgrade` rewrites no module and no data moves.
