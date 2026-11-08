# validation-new-app

A new app for each framework `init` detects and each package manager (ADR 0470).
The test writes a `package.json` and a lockfile, runs `init --yes`, then
`gen --snapshot` against the schema of an empty Supabase database, and
typechecks the generated core (`lib/supabase/index.ts` and what it imports)
with the workspace's `better-supabase`.

```sh
pnpm test
```

No Supabase CLI, Docker or database is needed. `src/empty-snapshot.json` is
`validation-declarative/snapshot.json` with its tables, views, columns and
functions removed.
