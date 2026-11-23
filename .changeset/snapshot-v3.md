---
"better-supabase": minor
---

Save snapshots as version 3. The file now records every function comment (not only the ones with tags), view column comments, the columns each check constraint covers, and each foreign key's deferrable, initially deferred and match type settings. Version 2 files still load and are read as version 3, and the new fields are optional, so nothing has to be regenerated. The JSON Schema is published as `schemas/snapshot-v3.json`; `snapshot-v2.json` stays.
