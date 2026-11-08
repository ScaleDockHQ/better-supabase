# 0390: Hold the declarative base layer to a fixture of its own

## Status

Accepted

## Context

The base layer promises three things that no existing fixture checks. After `upgrade`, `supabase db schema declarative sync --strict-coverage` finds nothing to change. A second `upgrade` keeps every object the app declares. Doctor fails on the patterns that break the first two. `tests/validation-centrakit` adopts every module against a large schema and needs the local stack, so it is slow and does not isolate these promises.

## Decision

`tests/validation-declarative` is a small app that owns `organizations`, `memberships`, `profiles` and `projects` in `supabase/schemas/010_app.sql` and `020_app_extensions.sql` (its own column, constraint, unique index, comment, policies, trigger and a view over the memberships helper), and adopts three modules. Its committed `supabase/migrations` file is the sync baseline, and `snapshot.json` stands in for a database in doctor.

- `upgrade.test.ts` rebuilds the module files from nothing, then runs a second `upgrade` after an app edit, and compares every file byte for byte.
- `sync.test.ts` runs the sync after the first and the second `upgrade`. The CLI plans against a shadow database, so no running stack is needed; the test skips when the Supabase CLI is missing.
- `doctor.test.ts` seeds one bad pattern per case and expects exit 1 with the one rule code: BS372 (do block), BS369 and BS371 (a prelude function declared again in an app file and in a module file), BS375 (duplicate policy), BS373 (`if not exists`), BS374 (insert in a module), BS376 and BS377 (coverage in both directions).

The `validation-lienlink` fixture of the plan stays open: it needs projection views, which the generator does not emit yet (the `projections` item).

## Consequences

The fixture runs in `pnpm test` in about 15 s. `db:gen` skips it, like CentraKit, because it has no app code. After a generator change that alters module output, run `upgrade`, then `supabase db schema declarative sync --no-apply --strict-coverage -f declarative_base` on an empty `migrations` folder, and refresh `snapshot.json` from the reset database.
