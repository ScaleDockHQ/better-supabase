---
"better-supabase": minor
---

`createPostgres()` session options take `statementTimeout`, which overrides the role's timeout for `asUser`, `executorFor` and `transaction`. `transaction()` without claims now applies `settings`, `readOnly` and `statementTimeout` too, and an `admin` query with no timeout to set runs without `begin` and `commit`.
