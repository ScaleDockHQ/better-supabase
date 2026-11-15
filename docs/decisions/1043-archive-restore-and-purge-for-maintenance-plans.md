# 1043: Archive, restore and purge for maintenance plans (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

ADR 1041 gives a record that a person enters an archive and a restore. A
maintenance plan is entered by staff, and `deletePlan` removed it with no way
back, while work orders it generated keep their own history.

## Decision

`maintenance` gets `archivePlan`, `restorePlan` and `purgePlan`.

- An optional `archived_at` column marks an archived plan.
- `archive` and `restore` are idempotent, return the plan and record
  `maintenance_plan.archived` and `maintenance_plan.restored` once.
- `purge` replaces `deletePlan` and `delete_maintenance_plan`. It needs
  `permissions.purge`, which falls back to the manage key, and records
  `maintenance_plan.purged`. `maintenance_plan.deleted` is gone.
- Read paths: an archived plan is never `due`, `generate_maintenance_work_orders`
  skips it, and the plan list hides it unless `archived` is set.

## Consequences

Breaking: `deletePlan`, `delete_maintenance_plan`, the `maintenance_plan.deleted`
event. The 0.66 to 0.67 guide has the old-to-new table.
