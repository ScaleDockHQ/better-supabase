# 0027: Squash the fixture migrations into a pg-delta baseline, and use the per-schema layout

- Status: accepted
- Date: 2026-10-14
- Supersedes: the "File layout" section of
  [0006](0006-pgdelta-and-native-stack.md)

## Context

Declarative Schemas 2.0 makes pg-delta the default diff engine for new
Supabase projects, and `supabase db schema declarative generate` writes one
file per object (`supabase/schemas/<schema>/<kind>/<object>.sql`). The
fixture still carried 91 migrations (54k lines). The first was the migra
baseline, with grants added by hand because migra missed them. Its schema
used the numbered layout from 0006, where one file such as `090_grants.sql`
granted on every table in a schema at once. A reader looking for a table's
grants or policies had to search several files, and a migration that
replayed the whole history took longer to review than the schema itself.

The SQL modules now support three workflows (`sql.workflow`: `pg-delta`,
`migra` and `migrations`), and the fixture is where the pg-delta one is
exercised.

## Decision

The fixture's own objects move to the per-schema layout the generator
writes. Each table file holds its grants, comments, policies and triggers,
and the bulk grants become one grant per table. Function bodies keep their
text, so the snapshots stay the same. The SQL module files move unchanged to
`supabase/schemas/_better_supabase/` with their default prefix, and the
Next.js example's `sql.dir` points there. Their data files stay in
`supabase/better-supabase-data/`.

The history is reset once to four migrations, written in this order:

1. `better-supabase sql sync` writes the extensions the module schemas need.
2. `pnpm supabase:sync baseline` writes the pg-delta baseline of
   `supabase/schemas`.
3. `<stamp>_fixture_data.sql`, by hand, holds what a diff skips: the RBAC
   role permissions, the `customer-logos` and `avatars` buckets, and the
   `authenticator` setting for PostgREST aggregates.
4. `better-supabase sql data` writes the module rows.

A reset from the new history gives the same rows, role settings and
publications as the old one, and `pnpm supabase:sync` finds no changes. The
only difference in the exported schema is the position of five columns that
old migrations had added with `ALTER TABLE`; they now sit where the schema
files declare them.

## Alternatives considered

- Keep the numbered layout and squash only: the bulk grants and the files
  that mix several tables stay, and the fixture keeps a layout no Supabase
  tool writes.
- Copy the output of `declarative generate`: it mixes the module objects
  into the fixture's files, so `sql sync` could no longer own the module
  files.
- Keep the history: it records how the fixture evolved, but nothing outside
  this repository applies it, and every new contributor replays all 91
  migrations.

## Consequences

The reset is an exception to "never change a pushed migration". It is safe
because the fixture's history is only applied to local stacks and CI. After
pulling it, run `pnpm supabase:reset`; a stack migrated with the old history
reports the old migrations as remote-only. New objects get their own file
under `supabase/schemas/<schema>/<kind>/`, and migrations keep coming from
`pnpm supabase:sync <name>`. We would revisit the layout if pg-delta starts
writing a different one.
