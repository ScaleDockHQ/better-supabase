---
"better-supabase": minor
---

`tags`: `blocks.tags.permissions` takes `create`, `update` and `delete`, each falling back to `manage`. With `options.patch: true`, `create_tag` takes an optional `slug` (checked against `^[a-z0-9]+(-[a-z0-9]+)*$`, `TAG_SLUG_INVALID`), and `update_tag` an optional `patch jsonb` that sets `name`, `slug`, `color`, `description` and `kind`, where `null` clears `color` or `description`; the client's `create` and `update` take them. An extra column that is `not null` without a `default` is written inside the insert, so `create` can set it. Without the option the functions keep their signatures.
