# 0387: The time-tracking block is time-entries

- Status: accepted
- Date: 2026-11-08
- Amends: 0130, 0246

## Context

The naming plan names entity blocks after their plural noun. `time-tracking`
holds the `time_entries` and `timesheets` tables and sits beside `billable-time`,
so `time-entries` is its name.

## Decision

- The block key, the SQL module, the subpath, the config key, the client and the
  docs page are `time-entries`: `better-supabase/blocks/time-entries`,
  `blocks.time-entries`, `db.$blocks.timeEntries`, `createTimeEntries`,
  `timeEntriesBlock`, `TimeEntriesOptions`, the `TIME_ENTRIES_*` constants and
  the `900_better_supabase_088_time_entries.sql` module file.
- The permission keys are `time_entries.read`, `.track`, `.approve` and
  `.manage`. `20261108075000_bsb_time_entries_names.sql` renames the rows of
  `better_supabase.permissions` in place, so every role grant and tenant override
  follows, renames the block's registry row in `better_supabase.blocks` and the
  block name `better_supabase.automations` stores. No row is added or removed.
- Rows of `api/naming.json` (`subpath`, `function`, `type` and `configKey`) let
  `codemod naming` rewrite imports and the `blocks` key of an app.

## Not done

`bulk` to `bulk-actions` and `rank` to `ratings` of the same plan paragraph have
not landed. `bulk` shares its token with entity names (`bulk_run`, `BulkRun`)
that keep their names, and `rank` is also the name of an ordering column, so each
needs an explicit mapping rather than the one-word replace this rename used.
