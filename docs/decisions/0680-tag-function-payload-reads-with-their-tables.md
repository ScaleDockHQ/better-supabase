# 0680: Tag function payload reads with the tables they read

- Status: accepted
- Date: 2026-11-11
- Amends: 0636

## Context

The perf audit listed cache tags for RPC payload reads as open. A page that loads a board or a
summary through a SQL function (`s.$fn.<name>(args)` in a read set) had no way to say which tables
the function reads, because the database cannot tell. Block reads already carry their module's
tables, so `bsb.tags` and `bsb.cached({ readSet })` tag those. An app's own function payload stayed
untagged, and a write to its tables left the cached payload stale until the app called
`bsb.tag(table)` by hand.

## Decision

`s.$fn.<name>(args, { tables })` takes the tables the function reads as an optional second argument.
`bsb.tags` and `bsb.cached({ readSet })` tag the entry with them, as they do for a table read, and
`bsb.tags` accepts a function call alone or in a list. `FunctionSpec` and `FunctionSpecOptions` are
exported types. Nothing changes for a call without options.

## Audit of the other 5b items

Checked against main (ADRs up to 0675): `@bsb` rpc, rollup stored and copy (0661), the access, list
and idempotency tags (0637), the doctor rule for row triggers (BS633), broadcast triggers and
`gen.types.also` (0663), the data-changing action mapper (0648), the bulk and board controllers
(0651), `useOptimisticAction`, `onEnded` and `onRejoin` (0631), `entryContext` and `cronHandler`
(0650), `observedFetch` (0649), batch reads (0670, and read sets batch block reads in `db.$many`,
0651), and every block item (0663, 0665 to 0669) are all on main. No work remains there.

Left on purpose:

- Tenant from the URL: `rootParams` covers it, so a second mechanism would only add a surface.
- A public API route kit: `withBetterSupabase` with `allow: apiKey` already serves it.
- Feeding `observedFetch` into `ctx.stats()`: stats already count Data API calls, so it would count
  twice.
- A function's tables read from the catalog: tags render and cache without a database, so the app
  names them.

## Consequences

An app that tags a function payload names its tables once, next to the call. A wrong list gives a
stale or an over-invalidated entry, the same as `bsb.tag`.
