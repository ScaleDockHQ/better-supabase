# 0856: Declare an import target in the manifest

- Status: accepted
- Date: 2026-11-14

## Context

EX-1211 found that the `imports` block could not say which blocks take rows.
The entities come from the SQL modules' `contributes.imports`, which exist only
while a module renders, so a page that lists them had to hard-code the names.

## Decision

A block manifest declares `importTarget: [entity, ...]`, the entities its SQL
module contributes to `import_upsert_batch`. Fourteen blocks (`accounting`,
`assets`, `attachments`, `catalog`, `contacts`, `custom-fields`,
`data-lifecycle`, `document-templates`, `inventory`, `invoices`, `orders`,
`organizations`, `quotes`, `tax`) declare theirs. `importTargetsOf(blocks)` from
`better-supabase/blocks/imports` lists every entity with its block and fails when
two blocks declare one entity. `tests/blocks/imports/targets.test.ts` keeps the
manifests equal to the SQL: a block declares targets exactly when its module
contributes imports, and the rendered imports module dispatches to every name.

## Alternatives considered

- Read the contributions at runtime: they need a render context.
- Generate the list from SQL: the manifest is what the catalog and the Blocks
  page already read.

## Consequences

The imports page lists every block that can take rows. A new import target
without a manifest entry fails the test.
