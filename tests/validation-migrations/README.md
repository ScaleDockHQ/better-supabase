# validation-migrations

The `migrations` and `migra` workflows on the tables of
`validation-declarative` (ADR 0470). `app/app.sql` holds the app's tables; the
test puts them in a migration stamped far ahead of now and runs `upgrade`.

- `migrations`: one migration named `<stamp>_better_supabase_modules_<hash>.sql`
  after the newest, no schema file, no table the app already has, and nothing
  written by a second run. A new block writes a second migration.
- `migra`: the module files land in `supabase/schemas`, and a second run keeps
  them byte for byte.
- `pg-delta`: no migration is written.
- Doctor's ownership rules pass under both, and on a Lite project.

```sh
pnpm test
```
