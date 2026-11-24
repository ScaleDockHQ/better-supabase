---
"better-supabase": patch
---

`gen` records each rendered SQL module that parsed, by content hash, in the CLI cache and parses
only modules it has not seen, and it imports the configured read sets once per run instead of once
per consumer. `gen --check` on the CRM validation project goes from 5.55 s to 5.3 s.
