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

The permission key, event type, hint and subject type maps, the stored-name
migration modules, the entity key aliases, `legacyHintOf` and doctor BS422 to
BS425 are removed. The table moves (`TABLE_RENAMES` and the `tableMoves`
migrations), the entity `formerly` noun and the function noun mapping stay.
They decide the names of a renamed install, and the TypeScript clients of nine
blocks still use the old nouns (`WorkItem`, `Engagement`, `Rule`). Removing
them means renaming those clients and the literal SQL names, so it moves to
the SQL and TypeScript rename step of Part 13. `entity-upgrade.ts` stays too:
it renames installed objects when `blocks.<name>.entities` changes, which is a
feature, and only its 0.47 key mapping is gone.
