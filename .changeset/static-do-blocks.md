---
"better-supabase": minor
---

Block schema files no longer contain a `do` block that creates objects. Policies on `realtime.messages` and `storage.objects`, the workflow World's types and row level security, and the flag and team upgrades are written as plain statements or moved to upgrade steps and data files. `teams` is at version 3: run `better-supabase upgrade` and `add --adopt`. `drive` and `ai-chat` each leave a function that `drive-files` and `share-links` declare, and doctor reports an object two block files declare. Lite and the Create check add the Realtime and Storage tables PGlite lacks.
