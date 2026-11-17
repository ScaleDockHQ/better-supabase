# 1089: Translatable audit summaries and ledger memos

- Status: accepted
- Date: 2026-11-17

## Context

Block functions write English prose into places an app shows to people: the
`summary` of an audit entry (`'posted entry ' || number`), the `memo` of a
ledger transaction a block posts (`Rent from 2026-11-01`) and the `memo` of
an accounting entry a block books (`Payment of INV-0001`, `Stock sale`). An
app in another locale can't translate them: the values are already joined
into one string, so a catalog would need one entry per number, date and
name. Apps either show English or rebuild the text from `metadata` with
their own rules per event type.

## Decision

Each writer stores a key and its values next to the prose, and keeps the
prose as the English fallback:

- The audit log gets `summary_key text` and `summary_params jsonb`.
  `audit_event` takes them as trailing defaults and stores
  `coalesce(summary_key, event_type)`, so every block action is keyed by its
  event type without a change at each call site. `ctx.record` takes an
  optional `summaryParams` (a `jsonb` expression) next to `summary`; the
  modules whose summaries name values pass it. Row entries get no key.
- The ledger's `transactions` table gets optional `memo_key` and
  `memo_params` columns (mapped to `null` like `memo` when an app's table
  lacks them). `ledger_post` takes them as trailing defaults, so callers that
  pass a memo only keep working. Block memo keys are the transaction kind
  (`lease.rent`).
- Accounting entries get the same two optional columns. A posting source's
  document sets `memoKey` and `memoParams` next to `memo`; the keys are
  `accounting.<source type>`, plus `accounting.reversal` and
  `accounting.opening_balances`. Saving an entry with a new memo clears them.
- Values stay raw: amounts as minor units, dates as ISO strings, ids and
  numbers as stored, so the app formats them in its own locale.
- `better-supabase/blocks/messages` exports `BLOCK_MEMO_MESSAGES`, every memo
  key with its English MessageFormat text. A test keeps it equal to the keys
  the modules write.

The proposal had `ctx.record` take `summary: { key, params }` and render the
English text from a template. About a hundred call sites build summaries in
SQL, and the event type already names each one, so the key defaults to the
event type and the summary text stays where it is. The summary catalog is
the event table on `extending/events.mdx`, not a second export.

## Alternatives considered

- A locale argument on every function. The database would need every
  catalog, and an entry written in one locale is wrong for a reader in
  another.
- Translating at read time from `metadata`. Each app repeats a formatter per
  event type, and the formatters drift from what the block wrote.
- A summary key per call site. It would differ from the event type only
  where one event has two wordings, which no block has.

## Consequences

Two columns on the audit log (module version 15), two optional ones on
ledger transactions (version 3) and on accounting entries. Existing rows
keep their prose and no key. Apps that ignore the keys see the same text as
before. Summaries outside the commerce blocks carry a key but no params
until their module passes `summaryParams`; their values stay in `metadata`.
