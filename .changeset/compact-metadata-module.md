---
"better-supabase": patch
---

`gen` writes the metadata module (`generated.meta.js`) with one line of JSON per table, function and enum instead of indented JSON. The metadata is the same; the module is about 40% smaller (1.45 MB to 0.83 MB for a 263-table schema), so `connect()` and cold starts parse less, and a schema change still shows up per table in a diff. Regenerate with `better-supabase gen`.
