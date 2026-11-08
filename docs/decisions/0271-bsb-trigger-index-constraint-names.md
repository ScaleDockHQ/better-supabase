# 0271: Name every generated trigger bsb_*, and end unique and exclusion names in `_key` and `_excl`

- Status: accepted
- Date: 2026-11-07
- Amends: 0246, 0247

## Context

The catalog test of ADR 0247 counted eight `better_supabase` triggers outside
`bsb_*`, seven index names outside `_idx`, `_key` and `_pkey`, and the rename
table could not move a trigger, an index or a constraint of an installed block.

## Decision

- Seven block triggers (`conversations_broadcast`, the two inbox broadcast
  triggers, `bookings_engagement`, `passes_credit_refund` and the two calendar
  auto-decline triggers) and the fixture's `permission_overrides` trigger carry
  `bsb_`.
- The two rate-limit unique indexes end in `_key`. Unique constraints end in
  `_key` (`flag_overrides_key`, `flag_revisions_key`), exclusion constraints in
  `_excl` (`bookings_no_overlap_excl`, and the same for time entries, shift
  assignments, leases, passes and calendar events). `naming_catalog.test.sql`
  accepts `_excl` and now allows no exception for triggers or indexes.
- `api/naming.json` rows take the kinds `trigger`, `index` and `constraint`
  (with `table`). `codemod naming` writes `alter trigger`, `alter index` and
  `alter table ... rename constraint` behind an existence check, and only for a
  name the project's SQL files mention.
- The fixture migration `20261107180013_bsb_trigger_and_index_names.sql`
  renames the objects and replaces `set_flag_override`, whose body names the
  constraint; no data moves, and the second strict-coverage sync is empty.

## Alternatives considered

Letting pg-delta drop and recreate the triggers and constraints works on an
empty fixture, but on an installed app it rebuilds the exclusion index of
`bookings` and `time_entries` for a rename.

## Consequences

Still open in the catalog test: 478 policies named `<table>_read` and similar,
1,872 check constraints that Postgres names itself, 33 timestamp columns
outside `_at`, 63 `organization_id` columns, and 31 `_user_id` or `deleted_at`
columns. Naming the checks has to reach every `drop constraint if exists
<table>_<column>_check` a module writes beside its `add constraint`, so it is a
change of its own.
