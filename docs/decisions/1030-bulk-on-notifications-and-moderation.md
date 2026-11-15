# 1030: Bulk on notifications and moderation

- Status: accepted
- Date: 2026-11-15
- Amends: 0854, 0858

## Context

ADR 0858 gave `tasks` the common `bulk(ids, action)` and left the other blocks
for lane Y4 (EX-1209). Of the blocks that still take many ids, `markRead`,
`markUnread` and `dismiss` on notifications run one set statement each, and
moderation decides one item per call. The `*Many` calls (`getMany`, `setMany`,
`recordMany`, `shareMany`) take a different value per row, and `audit.revert` is
all or nothing, so none of them fit `bulk(ids, action)`.

## Decision

`notifications.bulk(ids, "read" | "unread" | "dismiss", options)` runs the
existing set function through `bulkOfSet`: an id the function did not return is
`failed` with `not_found` (missing, not the caller's, or already in that state).
`moderation.bulk(ids, decision, options)` runs `decide` for each distinct id
through `bulk`, so a refused item lands in `failed`. Both manifests declare
`bulk: { actions }` on their entity. No SQL changes, and the old methods stay
because they are not replaced by a path that returns the same result.

## Alternatives considered

- Add `bulk_moderate` as a set function: the per-item checks and the log row
  already live in `moderate`, so a second function would drift from it.
- Remove `markRead(ids)` and `dismiss(ids)`: a breaking change for callers who
  read `{ count, items }`.

## Consequences

A notification list and the moderation queue write one bulk bar against the
common result. The `*Many` calls and `audit.revert` stay as they are.
