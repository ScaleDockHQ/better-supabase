# 1054: Archive and restore a care rule (lane Y2, slice 8)

- Status: accepted
- Date: 2026-11-15
- Amends: 1052

## Context

ADR 1052 gives the care rule an archive. `delete_care_rule` removes the rule, so
a team that stops using a dose range, interaction or duplicate therapy rule
loses its medications, bounds and message. `active = false` only skips the rule
in the evaluation: an inactive rule still lists and still accepts
`save_care_rule`, and nothing records that it was set aside on purpose.

## Decision

`archive_care_rule` and `restore_care_rule` need `clinical_decision_support.manage`
and record `care_rule.archived` and `care_rule.restored` once. Archiving an
archived rule, or restoring one that is not archived, returns it unchanged.

- The rules table gains an optional `archived_at` column, and the rule JSON
  carries `archivedAt`.
- `list_care_rules` hides archived rules by default and takes `include_archived`
  as a second argument, so the migration drops the one argument form.
- `evaluate_care_rules` skips an archived rule, so an archived rule raises no
  new alert. Alerts it already raised stay until the next evaluation resolves
  them, as they do after a delete.
- `save_care_rule` refuses an archived rule with `DECISION_SUPPORT_RULE_ARCHIVED`
  (SQLSTATE 55000). Restoring keeps the `active` flag.
- `delete_care_rule` becomes `purge_care_rule` and `care_rule.deleted` becomes
  `care_rule.purged`. The purge permission is `permissions.purge`, falling back
  to `manage`, so no role migration is needed (ADR 0851).

## Consequences

Breaking for callers of `deleteRule` and for sinks that match
`care_rule.deleted`; the changeset and the 0.66 to 0.67 guide have the
old-to-new table. A custom rules table without `archivedAt` gets neither
function and keeps the one argument list.
