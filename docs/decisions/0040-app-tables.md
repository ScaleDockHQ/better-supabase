# 0040: Render the app's own tables from `appTables`, and carry a Create design in the URL

- Status: accepted
- Date: 2026-10-18

## Context

Blocks cover the tables most apps share, but every app also has tables of its
own (`projects`, `tasks`). Until now an app wrote those by hand, and they
missed what the block files get for free: the scope column, row level
security, grants for the Data API, the `updated-at` trigger and a pgTAP test.
The Create canvas needs to let people draw those tables and add columns to
block tables, then hand the result to the CLI without a server: Create is a
static page, and `init --preset <url>` already reads a preset code from the
URL.

## Decision

A config key, `appTables`, declares the app's tables: lower snake names, a
closed list of column types, defaults from an allowlist and references to
another app table, `auth.users` or a block's logical table
(`src/config/app-tables.ts`, `src/config/types/app-tables.ts`). Each table
takes `scope`: `inherit` follows `sql.scope`, `user` and `none` override it.
`renderModules` writes one schema file, `900_better_supabase_app_tables.sql`,
and one pgTAP file from the key (`src/sql/modules/app-tables.ts`). App tables
aren't a block: no `SQL_MODULES` entry, no preset bit and no row in
`better_supabase.modules`, so `sql sync` writes and removes the file on its
own (`src/cli/sql/write.ts`, `src/cli/sql/sync.ts`).

The preset catalog gains `extraColumns`, the table a block's
`options.extraColumns` extends, so Create offers it without the SQL renderers.
A design (app tables, extra columns and canvas positions) is a second code on
the `/create` URL, `&design=`: a `0` version character and base64url of the
design's JSON compressed with `deflate-raw` (`src/preset/design.ts`). It
decodes strictly and is capped at 6000 characters. `init --preset` and
`apply --preset` decode it locally and write `appTables` and each block's
`extraColumns` into the config file (`src/cli/sql/design-edit.ts`).

The docs page `blocks/app-tables` and the codes page carry the examples;
there is no example app, since every example app's schema comes from blocks
the fixture already tests.

## Alternatives considered

Generating app tables as a block per table would reuse the module registry,
but blocks have fixed names, preset bits and a modules table row, and an
app's table names are its own. Writing plain SQL migrations from Create would
skip the config, so `sql sync`, `doctor` and the typed clients couldn't see
the tables. Storing designs on a server would remove the URL size cap but
give Create a backend and the CLI a network call; the cap has a fallback,
downloading the config. Packing a design into the BigInt preset code doesn't
fit free-form names and columns.

## Consequences

App tables follow the same scope and RLS rules as blocks, and the pgTAP file
proves it on every `supabase test db`. The file uses `add column if not
exists`, so under the `migrations` workflow a changed or dropped column
needs a migration by hand. A foreign key between two tenant-scoped app tables
doesn't check that both rows share a tenant. A new design field raises the
version character; revisit the format if designs routinely hit the cap.
