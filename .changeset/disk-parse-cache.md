---
"better-supabase": patch
---

The CLI keeps what each SQL file declares in `node_modules/.cache/better-supabase/parse/files.json`, so `doctor`, `upgrade` and `sync` parse only the files that changed since an earlier run. `--no-cache` skips it and `cache purge` deletes it.
