---
"better-supabase": minor
---

`upgrade` and `sync` read rendered modules from a cache in `node_modules/.cache/better-supabase` when the block names, the layout and the CLI version match, and `--no-cache` renders them again. Checks in generated SQL write a range as `x >= a and x <= b`. Doctor gains BS369 (an app file and a block module both declare an object) and BS370 (a schema file asks for `transaction=false`).
