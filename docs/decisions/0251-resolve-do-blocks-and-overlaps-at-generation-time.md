# 0251: Resolve the remaining do blocks and block overlaps at generation time

- Status: accepted
- Date: 2026-11-06
- Amends: 0250

## Context

ADR 0250 left 23 `do` blocks that create objects in the block files, and five
functions that two modules each declared. A schema diff can't see an object a
`do` block builds at run time, and the later of two definitions replaced the
first.

## Decision

`unwrapGuards` in `src/sql/pipeline/static.ts` runs first in `staticDdl`. It
writes a `do` block that guards one policy on `realtime.messages` or
`storage.objects` as that policy (every Supabase project has both tables), and
a `create type` that swallows `duplicate_object` as the statement. The
migrations workflow keeps the rerunnable form.

The other blocks are resolved by the module that wrote them:

- `workflow-sdk` writes `enable row level security`, `revoke` and `grant` for
  each table the World's DDL creates, read from that DDL when the file is
  rendered. The 5.0 timestamp conversion moves to the module's data file.
- `flags` moves the version 2 constraint cleanup into its version 3 upgrade
  step, and `teams` moves the inbox team copy into a new version 3 upgrade
  step. The schema files keep the foreign key.
- `legal-entities` moves the number-key restore, which reads the rows before it
  swaps a key, and the per-record unique constraint cleanup into its data file.
- `drive` declares `drive_node_json` only when no `drive-files` module will,
  and `ai-chat` leaves its four share functions to `share-links` when that
  block is installed, with the grants they had. `BLOCK_OVERLAPS` is gone, so
  doctor reports any object two block files declare.

Lite adds the `realtime` and `storage` tables to PGlite when a schema uses
them, and the Create prelude declares them, because module files no longer
check that the tables exist.

## Alternatives considered

Keeping the guards in the files would leave PGlite working without a shim and
leave 23 objects invisible to the diff. Writing the policy statements into 13
templates by hand would repeat what one pass over the statements does.

## Consequences

The repository's `supabase/` folder is regenerated, with one migration that
adds the inbox foreign key, one that carries the share function bodies, and one
upgrade step for teams. `supabase db schema declarative sync --strict-coverage`
reports no changes and the 172 pgTAP files pass. Module data files for teams,
workflow-sdk and legal-entities change, so installed apps run `add --adopt`.
