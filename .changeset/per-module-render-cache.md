---
"better-supabase": minor
---

`upgrade`, `sync` and `doctor` render each block module once per set of inputs it reads. A change to the config or to an app schema file renders only the modules that read what changed, and serves the others from `node_modules/.cache/better-supabase/modules/renders.json`. `--no-cache` skips it and `cache purge` deletes it.
