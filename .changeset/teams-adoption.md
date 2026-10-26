---
"better-supabase": minor
---

`teams`: `blocks.teams.permissions` takes `create`, `update`, `delete` and `members`, each falling back to `manage`. With `options.patch: true`, `create_team` takes an optional `slug` and `update_team` an optional `patch jsonb` that sets `name`, `slug` and `description` (where `null` clears the description); the client's `create` and `update` take a trailing options object for them. With `options.restore: true`, the new `restore_team` makes an archived team active again and records `team.restored`, and the client's `restore(id)` calls it. An extra column that is `not null` without a `default` is written inside the insert. Without the options the functions keep their signatures.
