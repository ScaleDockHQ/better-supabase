---
"better-supabase": patch
---

`upgrade` no longer renders every module that adds app columns to a block table when an app file adds a column to one table. A module now reads only the entry of its own table in the app's added columns, so adding the first column to a table re-renders 4 modules on the CentraKit fixture instead of 30. The generated SQL is the same.
