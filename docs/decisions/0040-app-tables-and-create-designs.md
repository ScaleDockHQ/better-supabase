# 0040: Declare app tables in the config and carry Create designs in a second code

- Status: accepted
- Date: 2026-10-18

## Context

The Create page (`/create`) shows the schema a preset installs, but the
tables an app adds next to the blocks live outside better-supabase: people
write them by hand, with their own tenant column and row level security,
and the policies drift from the ones the blocks use. The canvas editor
needs a place to put the tables and columns someone draws, and a link that
reopens the same canvas. The preset code (`1...`) is a fixed-width BigInt of
field indexes and block bits (ADR 0029 and the codes page), so it can't hold
free-form tables. The top-level `tables` config key already means codegen
overrides, so the new key needs another name.

## Decision

`appTables` is a config key: tables in `public`, each with `columns` from a
closed type list (money as `bigint` minor units with a currency column, per
ADR 0024 and 0037), `references` to another app table, `auth.users` or a
block's logical table, `scope` (`inherit`, `user`, `none`) and
`timestamps`. `appTablesOf` (`src/config/app-tables.ts`) validates it, and
the `app-tables` SQL module renders it after the blocks, with the tenant
column and the policies the blocks use, foreign keys to block tables
through `ctx.table()` so renames resolve, and `create table if not exists`
plus `add column if not exists` so re-running `sql sync` is safe. Columns on
block tables use the existing `options.extraColumns`, and the catalog lists
which tables take them.

A design (`CreateDesign`: app tables, extra columns and canvas positions)
travels in a second URL parameter, `&design=`, as a version character `0`
and deflate-raw compressed JSON in base64url, at most 6000 characters.
`better-supabase/preset` exports `encodeDesign`, `decodeDesign`,
`designOf`, `designConfig` and `designConfigSource`, and `init` and
`apply` decode a `/create` URL locally, with no network call. Positions
never reach the config.

## Alternatives considered

- Widen the preset code to hold tables. It would end the fixed-width code
  and every frozen fixture, and a code of free-form tables can't stay short.
- Store designs on the server behind a short id. It needs storage, accounts
  or abuse limits, and `init` would need the network.
- Let people write the SQL themselves next to the blocks. It is what they do
  today, and the policies drift from the blocks' scope.

## Consequences

An app can declare its own tables in the same file as its blocks and get
the same scope checks. The `app-tables` module is the one module whose
tables the app names, so its validation has to stay strict (a closed type
list and an allowlist of defaults) to keep the generated SQL safe. A design
larger than 6000 characters can't be shared as a link; Create offers the
config to download instead. Revisit if people need column types or
constraints outside the list, or if links routinely hit the cap.

The marketing app adds `html-to-image` (pinned at 1.11.13 in the catalog)
to export the diagram as PNG and SVG, and `sonner` for its toasts. Neither
reaches the library.
