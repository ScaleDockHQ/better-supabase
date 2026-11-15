---
"better-supabase": minor
---

`drive.bulkShare(items)`, `filespace.bulkShare(input)` and `customFields.bulkSet(input)` give each row its own value and return the common `{ succeeded, failed }` report, named by node id, `type:id` principal and field key. They take at most 500 rows and do not stop at the first failure; a repeated id fails with `BULK_DUPLICATE_ID`.

`drive.shareMany`, `filespace.shareMany` and `customFields.setMany` are deprecated and removed in 0.70. They keep working and keep stopping at the first failure.

| Old                                         | New                                                  |
| ------------------------------------------- | ---------------------------------------------------- |
| `drive.shareMany({ ids, grants })`          | `drive.bulkShare(ids.map((id) => ({ id, grants })))` |
| `filespace.shareMany({ id, ... })`          | `filespace.bulkShare({ id, ... })`                   |
| `customFields.setMany({ subject, inputs })` | `customFields.bulkSet({ subject, inputs })`          |
