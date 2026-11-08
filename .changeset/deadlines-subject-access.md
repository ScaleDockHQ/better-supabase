---
"better-supabase": minor
---

`deadlines` follows the read access of each deadline's subject, and `compute` clears the groups a newer rule version dropped. See ADR 0242.

- The module reads `blocks.deadlines.on`, or `config.subjects` when it is unset. With subjects, the `deadlines` read policy, `list`, `compute`, `recompute` and `satisfy` also need the subject row in the tenant and its read permission (key, provider `rows`, `owner` or `check`). `list_deadlines` is now security invoker, so the subject table's policies apply too. A subject type that isn't listed is hidden and refused with `DEADLINE_FORBIDDEN`. Without subjects nothing changes.
- `compute` without a group deletes the subject's pending rows of that jurisdiction and kind whose group the applying version no longer has. Satisfied rows stay as history.

Run `better-supabase upgrade` and generate a migration. If your app has `config.subjects`, register (or list in `blocks.deadlines.on`) every subject type you compute deadlines for, or those rows become invisible.
