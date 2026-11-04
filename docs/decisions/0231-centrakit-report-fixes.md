# 0231: Run account helpers over a transport and ship the CentraKit report fixes

- Status: accepted
- Date: 2026-11-04

## Context

The CentraKit report listed 22 gaps between the library and a production app. Most were
places where the app wrote a shim: account helpers that needed a direct Postgres
connection, block clients typed without the app's own columns, rows from `$client` that
skipped the casing and codecs, and test helpers that needed a stack.

## Decision

`endSessions`, `lastSignIns` and `suspendAccount` take a `BlockTransport` besides a
`SqlClient`, and `better_supabase.end_sessions(p_user)` lets the service role end sessions
over the Data API. `gen` includes the block API schemas in typegen. A generated block entry
may carry `columns`, which `generatedOptions` turns into the `fields` option.
`db.$decode(table)` reads rows with database names into the table's shape and returns a
`Result`. `authErrorKind` classifies Auth errors in one table, `SupportApi` accepts a
`SupportCaller`, and `bsb.action` takes `guard` and `result`. `createFakeClient` joins
`better-supabase/testing`, and the pgTAP helpers gain `authenticate_as(email)` and
`authenticate_as_issued`.

## Alternatives considered

- Thread the database type through `createNext` (B6). The generic does not satisfy the
  `SupabaseClient` constraint inside the adapter without casts, so it stays open.
- Read the custom access token hook from `config.toml` in `gen` (B14). The module context
  has no access to the introspection snapshot, so the hook is passed by name.

## Consequences

Apps can drop the shims for these gaps. The items not done here (B6, B8, B13, B17 to B19,
B21, B22 and the `bound` option of B9) stay in the report for a follow-up.
