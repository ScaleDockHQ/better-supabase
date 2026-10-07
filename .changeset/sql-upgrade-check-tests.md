---
"better-supabase": patch
---

`sql upgrade --check` no longer reports a module as behind because of the pgTAP files it generates for your tables. Those files carry no module version, so the audit tests counted as the `audit` module at version 1 and the check failed on every project with an audited table. `sql upgrade` now leaves them to `sql sync --check`.
