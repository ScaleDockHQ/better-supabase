---
"better-supabase": minor
---

Conditional updates and bulk writes that return rows. `update(key, patch, { where })` adds conditions the row must meet (a tenant, a status), and a row with this key that does not match returns `not_found` in one request, without the probe `expect` needs. `expect` now takes the same operators as `where` (`{ status: { in: [...] } }`); plain values still mean equality, and a mismatch still returns `stale`. `updateMany` and `deleteMany` take `returning: true`, with `select` and `include`, and then return the written rows instead of `{ count }`. On a `softDelete()` table, `deleteMany({ returning: true })` keeps `RETURNING` on the update it becomes. Nothing changes for calls without the new options.
