# 1075: Bulk items for a value per row

- Status: accepted
- Date: 2026-11-15
- Amends: 0854, 1030

## Context

ADR 1030 left the `*Many` calls out of `bulk(ids, action)` because they take a
different value per row (EX-1209). Of the nine that exist, three act on rows
that already exist and stop at the first failure: `drive.shareMany`,
`filespace.shareMany` and `customFields.setMany`. The others do not fit a
per-row report: `getMany` is a read, and `usage.recordMany`, `usage.consumeMany`,
`audit.recordMany`, `observations.recordMany`, `webhooks.publishMany` and
`notifications.sendMany` create rows, so no id exists before the call. The usage
and observation batches are all or none by design, and the audit, webhook and
notification batches already return one `Result` per event.

## Decision

`bulkItems(items, apply, options)` in `src/core/bulk.ts` returns the same
`BulkReport` as `bulk`: each item is `{ id, ...value }`, the report names it by
`id`, the limit (500) counts items, and a thrown or failed item lands in
`failed`. A repeated id fails with `BULK_DUPLICATE_ID` and does not run.
`drive.bulkShare(items)`, `filespace.bulkShare(input)` and
`customFields.bulkSet(input)` use it. The old `shareMany` and `setMany` keep
their result shape and stop-at-first-failure behavior, are marked `@deprecated`
and are removed in 0.70. They share the per-row function but cannot call the new
methods, because their results (the grants and values written) differ from the
report. The migration guide and the changeset carry the old-to-new table.

The other `*Many` calls stay as they are: they are reads or batch creates, and
an id list cannot describe them. EX-1209 closes with that reason.

## Alternatives considered

- Make every `*Many` a `bulk(ids, action)`: the creates have no ids.
- Remove the old calls now: a breaking change with a replacement that returns
  less.

## Consequences

An entity with a value per row writes one bulk bar against the common report.
The deprecated calls cost one line each until 0.70.
