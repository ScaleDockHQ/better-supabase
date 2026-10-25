---
"better-supabase": minor
---

`teams`: `blocks.teams.permissions` takes `create`, `update`, `delete` and `members`, each falling back to `manage`. `create_team` takes an optional `slug`, `update_team` an optional `patch jsonb` that sets `name`, `slug` and `description` (where `null` clears the description), and the new `restore_team` makes an archived team active again and records `team.restored`. The client's `create` and `update` take a trailing options object for them, and `restore(id)` is new. An extra column that is `not null` without a `default` is written inside the insert. Positional calls with the old arguments keep working.
