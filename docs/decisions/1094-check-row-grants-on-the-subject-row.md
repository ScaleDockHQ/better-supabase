# 1094: Check row grants on the subject row

- Status: accepted
- Date: 2026-11-19

## Context

`config.recordTypes.<type>.permissions` takes a plain key or an entry with
`rows`, `owner` or `check`, which `can_subject` and the subject read check
already run on the subject row. The `attachments` upload and manage checks
(`subjectAccess` in `src/sql/subjects.ts`) reduced such an entry to its key and
checked it in the tenant only, and the `deadlines` read gate checked its read
key in the tenant before the subject check ran. An authorization provider that
grants a key per row (own or team level) answers `false` for the tenant, so a
member could not attach a file to a record they own, nor read the deadlines of
one.

## Decision

`subjectAccess` checks a registered action whose entry has `rows`, `owner` or
`check` on the subject row: an `exists` over the subject table, scoped to the
row's tenant, that runs the same grants as `can_subject` (the key in the
tenant, the provider's row grants, the owner column, the check function). The
attachments policies qualify the row's columns, so the subquery can't bind them
to the subject table's own columns. A type the block overrides with
`on.<type>.permissions` keeps the plain key.

In `deadlines`, a subject type whose registered read is such an entry, with the
same key as the module's read key, passes the read gate for a member of the
tenant, and the subject check decides. `list_deadlines` and `page_deadlines`
let a member of the tenant in when such a type exists; their read policy still
filters the rows.

## Alternatives considered

- Asking the provider for "holds the key at any level" in the tenant check. It
  lets an own-level member through for every record of the type, which is the
  leak the row check exists to prevent.
- Calling `can_subject` in the policies. It costs one function call per row in
  a list; the inlined `exists` keeps the subject table's index and the
  provider's set function.

## Consequences

Apps that register `{ key, rows }` (or `owner`, `check`) for `upload`,
`manage` or `read` get row-level checks without a workaround view or trigger.
Apps that register plain keys see no change. A provider row function now runs
inside the attachments insert policy, once per inserted row.
