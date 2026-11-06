# 0245: Upgrades start at 0.53, and removed names have no alias

- Status: accepted
- Date: 2026-11-06

## Context

The library carried deprecated APIs, a rename shim for each of the 0.15, 0.46
and 0.47 releases, a codemod for every release from 0.4, a table of moved CLI
commands and doctor rules that only flagged removed forms. Both consumers run
0.53. Every later change had to work around code that only served apps that
no longer exist.

## Decision

This release upgrades from 0.53 only. An app on an older version upgrades to
0.53 first with that release. Nothing keeps an alias, a shim or a compatibility
switch, and that includes the new spellings of ADR 0246.

Removed in this step: `$apiResult`, the `triggerSql` overload, the module
`version` option, the `openapi` config key (`specs` is the only key), the
`canApprove` template and `approvals.distinctApprover` (`isApprover` always
refuses the requester), `BLOCK_EVENT_RENAMES`, the 0.15 block renames and the
`bs_` prefix and `modules` table upgrade steps, the moved-command table, doctor
BS415, BS418 and BS509, the codemods 0.4 to 0.53 and their JSON export, and the
migration guides before 0.53. `read-many` stays as a tool, not a migration. The
`@deprecated` line the generator reads from an app's own SQL comment stays,
because it is a feature.

One codemod per release replaces them. `codemod naming` applies the rename
table of ADR 0246.

## Alternatives considered

Keeping the shims for one more minor release would repeat the cost of the
last three. A codemod chain from 0.4 would test paths nobody takes.

## Consequences

The 0.46 and 0.47 stored-name migration modules, `core/renames.ts`,
`legacyHintOf`, `spec.formerly`, `entity-upgrade.ts`, the `formerKeys` types
and doctor BS423 to BS425 are still in the tree. They share the table-move and
subject-type paths of the SQL modules, so removing them changes generated SQL
and needs its own golden and migration review. The plan's later stages remove
them.
