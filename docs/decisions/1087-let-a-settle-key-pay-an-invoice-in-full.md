# 1087: Let a settle key pay an invoice in full

- Status: accepted
- Date: 2026-11-16

## Context

Each invoice action checks one permission key, set per action in
`blocks.invoices.permissions`. Apps often split payments into two permissions:
one that records any payment or refund, and a narrower "mark paid" that only
settles an invoice in full. With one key per action, the narrower permission
could not call `record_invoice_payment` at all, so apps checked it in their
own code and called the function with a broader key.

## Decision

`permissions.settle` names a second key for `record_invoice_payment`. The
function accepts a caller with `payment` as before, or with `settle` when the
amount is positive and equals the invoice's open balance (so it never books a
refund) or the reference was already
recorded, so `markPaid` and its retries work with either key. Without
`settle` the key defaults to `payment` and the function renders the same SQL
as before. The check lives in `src/sql/modules/invoices-functions.ts`
(`settleKey`) and the key in `OPTIONAL_MODULE_PERMISSIONS`.

## Alternatives considered

- Let every action accept a list of keys. It changes the config type of every
  block and the `can()` rendering for all of them, for one case that needs a
  narrower meaning, not just another key.
- A separate `settle_invoice` function. It would repeat the payment path (the
  ledger post, the status change, events and hooks) or call
  `record_invoice_payment` through a second permission check, for the same
  result `markPaid` already gets.

## Consequences

An app maps its "mark paid" permission to `settle` and keeps "record payment"
on `payment`. A caller with only `settle` who sends a partial amount gets
`INVOICE_FORBIDDEN`. Revisit when a second block needs an action that accepts
a narrower key under a condition.
