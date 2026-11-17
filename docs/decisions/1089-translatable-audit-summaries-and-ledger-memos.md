# 1089: Translatable audit summaries and ledger memos

- Status: proposed
- Date: 2026-11-17

## Context

Block functions write English prose into two places an app shows to people:
the `summary` of an audit entry (`'Leave requested from ' || starts_on ...`)
and the `memo` of a ledger transaction that a block posts (a payout, an
accrual, an invoice payment). An app in another locale can't translate them:
the values are already joined into one string, so a catalog would need one
entry per number, date and name. Apps either show English or rebuild the text
from `metadata` with their own rules per event type.

## Decision

Proposed, not implemented. Each writer stores a key and its values next to
the prose, and keeps the prose as the fallback:

- `audit_log` gets `summary_key text` and `summary_params jsonb`. `ctx.record`
  takes `summary: { key, params }`, renders the English text into `summary`
  as today, and writes the key and values. Keys follow the event type,
  `<entity>.<verb>` (`leave_request.created`), so an app's catalog can cover a
  block's events from the event table on `extending/events.mdx`.
- The ledger's `transactions` table gets optional `memoKey` and `memoParams`
  columns (mapped to `null` like `memo` when an app's table lacks them).
  `ledger_post` takes them as trailing defaults, so callers that pass a memo
  only keep working.
- Values stay raw: amounts as minor units with their currency, dates as ISO
  strings, ids as ids, so the app formats them with its own locale.
- The block's `messages` export lists the keys with their English
  MessageFormat text, as it does for hint codes today.

## Alternatives considered

- A locale argument on every function. The database would need every
  catalog, and an entry written in one locale is wrong for a reader in
  another.
- Translating at read time from `metadata`. Each app repeats a formatter per
  event type, and the formatters drift from what the block wrote.

## Consequences

Two columns on the audit log and two optional ones on ledger transactions,
written by every module that records a summary or posts a memo, so the change
touches many modules and lands with a version bump of the audit and ledger
modules. Existing rows keep their prose and no key. Revisit the shape when
the first block ships keys.
