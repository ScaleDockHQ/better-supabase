---
"better-supabase": minor
---

`tasks.bulk(ids, action, options)` archives, restores or removes many tasks with the common bulk shape: `{ succeeded, failed: [{ id, error }] }`, with ids the set statement skipped as `failed` with `not_found`, and `BULK_TOO_MANY` beyond 500 ids. The array overloads of `archive`, `restore` and `remove` keep working. `TaskBulkAction` is exported from `better-supabase/blocks/tasks`.
