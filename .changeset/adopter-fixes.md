---
"better-supabase": minor
---

Fix seven issues an adopter reported, around `$rpc` types, `findMany`, `DbException` and PowerSync.

- `gen` types a `returns table` column through a `not null` domain as non-null, and prints a notice that points to `@notNull` for a function whose columns stay nullable. Function arguments stay `| null`, which only widens what you can pass.
- A top-level `_count`, `_sum`, `_avg`, `_min` or `_max` in `findMany` and the other reads is now a type error and returns an `invalid_request` error. Before, the key was silently ignored, so code that passed one gets an error now: move it into `include: { _count: { notes: true } }`, or call `aggregate()` for the table itself.
- `DbException` has the `DbError` fields as its own properties (`kind`, `status`, and `code`, `details`, `hint` and `table` when set), and the `DbError` as its `cause`.
- PowerSync and Expo SQLite run includes (nested, filtered, ordered, limited and `required`), related counts and related aggregates as one SQL statement. `checkSqlite` also takes a query spec from `betterSupabase.spec`.
- `createUploadConnector` takes `onError`, which reports a failed `getSession` (`phase: "credentials"`, kind `unauthorized` or `network`) and uploads that stay queued for a retry (`phase: "upload"`).
- `UploadRepository<Insert, Key>` is typed by the table, so generated repositories fit it without a cast. `uploadRoute(repository, { put: "create" })` makes an insert-only route for write-once tables: a `PUT` calls `create`, and a conflict counts as applied.
