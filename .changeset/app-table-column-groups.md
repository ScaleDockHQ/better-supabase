---
"better-supabase": minor
---

App tables take `columnGroups`: `tables.<name>.columnGroups.<group> = { columns, update }` renders a `before update` trigger that raises `42501` when a caller signed in as `authenticated` or `anon` changes a listed column without the `update` permission in the row's tenant. Doctor adds BS362 for an update policy that checks a permission ending in `.read` or `.view`.
