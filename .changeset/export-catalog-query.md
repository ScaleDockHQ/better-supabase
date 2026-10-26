---
"better-supabase": patch
---

`better-supabase/create/lite` now exports `catalogQuery` and `readCatalog`, which the 0.22.0 notes for `importProject` already named. Run the query yourself, pass its rows to `readCatalog`, then pass the result to `designFromCatalog`.
