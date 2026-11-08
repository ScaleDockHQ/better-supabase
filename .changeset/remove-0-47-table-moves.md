---
"better-supabase": minor
---

Module upgrades no longer rename the tables 0.47 renamed (`engagements` to `activities`, `work_items` to `tasks` and the others in ADR 0130). Upgrades start at 0.53, where those tables already carry their names. `codemod naming` also moves the `bsb.*` policy helper functions to `better_supabase`, and only when the project's SQL names them.
