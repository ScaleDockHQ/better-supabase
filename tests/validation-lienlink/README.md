# validation-lienlink

Lienlink's shape (ADR 0391). The blocks own the `better_supabase` tables, and
the app's views in `public` project them (`030_projections.sql`), with an
`instead of insert` trigger on `job_attachments`. The app also alters block
tables (`020_block_alters.sql`: a membership id, team keys and checks, a stored
generated `job_id`), keeps a composite foreign key into the teams table, an
audit trigger on `jobs`, a trigger on `auth.users` and the end-state grants.

The tests hold it to the same promises as `validation-declarative`: an empty
`supabase db schema declarative sync --strict-coverage` after the first and the
second `upgrade`, every app object kept by a second `upgrade`, and doctor
failing on seeded patterns.

`supabase/tests/projections.test.sql` is a pgTAP file for the projection shape:
the views and their `security_invoker` option, the `instead of` insert trigger,
the stored generated column, the composite foreign key and the app's triggers
beside the blocks'. `better-supabase upgrade` leaves it alone. Start the
fixture's stack with `supabase start` in this folder, then run `supabase test db`.

```sh
pnpm test
pnpm sql:check
```

To refresh the baseline after a module changes, remove
`supabase/migrations/*_declarative_base.sql` (keep the role-timeouts migration),
run `better-supabase upgrade`, then
`supabase db schema declarative sync --no-apply --strict-coverage -f declarative_base`,
reset a local stack from it and write the snapshot with `introspect`.
