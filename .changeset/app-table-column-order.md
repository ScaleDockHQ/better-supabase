---
"better-supabase": minor
---

A block that adds columns to your own table now adds a column before the columns whose checks read it, so applying the generated file no longer fails with `column "user_id" does not exist` on the contacts block over an existing table.
