# 0388: The bulk block is bulk-actions

- Status: accepted
- Date: 2026-11-08
- Amends: 0130, 0246, 0387

## Context

The naming plan names a capability block after the noun it adds, and `bulk` is
an adjective. `bulk-actions` is the block that runs one action over many records.

## Decision

- The block key, SQL module, subpath, config key, client and docs page are
  `bulk-actions`: `better-supabase/blocks/bulk-actions`, `blocks["bulk-actions"]`,
  `db.$blocks.bulkActions`, `createBulkActions`, `bulkActionsBlock`,
  `BulkActionsEvents`, `BulkActionsOptions`, the `BulkActions` client type and the
  `900_better_supabase_069_bulk_actions.sql` module file.
- The permission keys are `bulk_actions.run` and `bulk_actions.*`.
  `20261108082000_bsb_bulk_actions_names.sql` renames the rows of
  `better_supabase.permissions` in place, so grants and overrides follow, and
  renames the registry row and the block name automations store.
- The names of the run itself keep the entity noun, because `bulk_run` is the
  entity (ADR 0130): the `bulk_runs` table, `start_bulk`, `bulk_apply`,
  `bulk_run.completed`, `BulkRun`, `BulkInput`, `BulkResult` and the `BULK_*`
  hint codes.
- Rows of `api/naming.json` (`subpath`, `function`, `type` and `configKey`) let
  `codemod naming` rewrite imports and the `blocks` key of an app. The config key
  codemod quotes a new key that is not an identifier.

## Not done

`rank` to `ratings` has not landed (see ADR 0387).
