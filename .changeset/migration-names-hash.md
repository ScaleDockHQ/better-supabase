---
"better-supabase": minor
---

Every migration the CLI writes is named `<stamp>_better_supabase_<name>_<hash>.sql`. The stamp is later than every migration in the folder, so `upgrade` never shares a version with another tool, and the hash of the statements lets a repeated run write nothing. Migrations from earlier releases are still found by their suffix.
