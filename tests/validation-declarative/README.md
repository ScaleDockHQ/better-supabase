# validation-declarative

An app that owns its tables in `supabase/schemas` and adopts the
`organizations`, `memberships` and `profiles` modules. The tests hold it to
three promises (ADR 0390):

- After `better-supabase upgrade`, `supabase db schema declarative sync
  --no-apply --strict-coverage` reports no changes.
- A second `upgrade` keeps every object the app's files declare.
- Doctor fails on seeded ownership and coverage patterns.

```sh
pnpm test
pnpm sql:check
```

The sync test needs the Supabase CLI and Docker for the shadow database, not a
running stack. `supabase/migrations` holds the baseline and `snapshot.json`
stands in for a database in doctor. To refresh both after a module changes,
remove `supabase/migrations/*_declarative_base.sql` (keep the role-timeouts migration), run `better-supabase upgrade`, then
`supabase db schema declarative sync --no-apply --strict-coverage -f declarative_base`,
reset a local stack from it and write the snapshot with `introspect`.
