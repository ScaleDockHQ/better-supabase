# 0233: Close the CentraKit gaps in 0.54

- Status: accepted
- Date: 2026-11-05

## Context

CentraKit, the largest consumer, reported ten gaps while moving to 0.53. Each one cost
it a shim or a slow path: required columns that have defaults, an audit trigger that
refused the restricted details table, an approvals function that ran per request, a doctor
false positive on tagged dollar quotes, an export docs named but the package lacked, avatars
in Storage, a synchronous context factory, N-call bulk task actions, service clients without
per-block settings, and three smaller gaps.

## Decision

- Input schemas of `columns` treat a `not null` column with a default as optional.
- The audit statement trigger writes the restricted rows from the transition tables.
  Module version 11.
- `approval_eligible_ids` is set based, so each permission is checked once per tenant and
  permission pair.
- BS243 measures the quoted literals inside a function body, not the body's own dollar quote.
- `better-supabase/auth` exports `authErrorKind`.
- `blocks.profiles.options.avatarSource` is `"url"` or `"path"`; `message_authors` reads it.
- `withContext` takes an async factory. A bootstrap entry carries `tables`, declared or derived
  from the function body at gen time, and `bsb.bootstrap` tags its cache entry with them.
- Tasks gain `archive_tasks` and `delete_tasks` (module version 5), and the client takes id
  lists.
- `serviceBlocks(admin, { blocks })` applies per-block options through `block.with`.
- BS315 is an error. `tests.authenticate_as` looks users up through `security definer` helpers
  while it stays `security invoker`, because `set role` is refused in a definer function.

## Alternatives considered

- Making `authenticate_as` itself `security definer`. Postgres rejects `set role` there.
- Reading bootstrap tables only from the function body. A body can call other functions or build
  SQL dynamically, so a declared list wins and the derived list is the fallback.
- Keeping BS315 a warning for one more minor. The warning had been announced in 0.53 and a
  CI that ignores warnings never saw the gap.

## Consequences

Projects with unaudited tables fail doctor until they audit or exempt them with a reason. The
0.53 to 0.54 guide lists the steps. `gen` rewrites the pgTAP helpers, and `upgrade` renders the
audit and tasks functions.
