# 0858: Tasks take the common bulk call

- Status: accepted
- Date: 2026-11-14

## Context

EX-1209 found three bulk shapes. ADR 0854 added `bulk(ids, action)` with
`{ succeeded, failed }` and a limit, and `bulk-actions` has it. The array
overloads, such as `tasks.remove(taskIds)`, still return their own
`{ ids, skipped }`. The per-block `*Many` calls (`getMany`, `setMany`,
`recordMany`, `shareMany`) read or write different values per row, which
`bulk(ids, action)` cannot express.

## Decision

`tasks.bulk(ids, action, options)` takes `archive`, `restore` or `remove` and
runs the existing set statement once (`bulkOfSet` in `src/core/bulk.ts`). The
ids the statement skipped are `failed` with `not_found`. The manifest declares
`bulk: { actions }` on the task entity. The array overloads stay: removing them
would break callers for no gain, and the new call is additive. The `*Many`
calls stay as they are.

## Alternatives considered

- Remove the array overloads: a breaking change, and `{ ids, skipped }` is
  still the shape of the SQL function.
- Turn each `*Many` call into a `bulk` action: the inputs differ per row, so
  the action name would hide the real input.

## Consequences

Other entities with a set statement adopt `bulk` with `bulkOfSet` as their
lane reaches them. A caller who wants the common shape on tasks has it today.
