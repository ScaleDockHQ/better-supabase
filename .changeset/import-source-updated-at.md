---
"better-supabase": minor
---

An import item can carry `sourceUpdatedAt`. Apply skips a row whose source time is not newer than the stored one, and `diffItems` reports created, changed and unchanged rows the same way.
