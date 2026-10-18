---
"better-supabase": minor
---

Breaking: every amount with a currency in the deals, quotes, invoices, pipelines and employees blocks is a `Money` value (`{ amount: bigint, currency }` from `better-supabase/commerce`) instead of a bare `bigint`. Build one with `money(amount, currency)`. Line inputs, totals, payments, aging buckets, forecasts, board totals and contract salaries all change, and the separate `currency` input of a contract is gone because `salary` carries it. Target goals and progress stay `bigint`.

| Old                                                                  | New                                                                           |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `deals.create(org, { amount: 4_800_000n, currency: "EUR" })`         | `deals.create(org, { amount: money(4_800_000n, "EUR") })`                     |
| `{ description, unitAmount: 9_500n }`                                | `{ description, unitAmount: money(9_500n, "EUR") }`                           |
| `invoices.recordPayment(id, { amount: 137_940n })`                   | `invoices.recordPayment(id, { amount: money(137_940n, "EUR") })`              |
| `deals.forecast(org, { currency: "EUR", target: 60_000_000n })`      | `deals.forecast(org, { currency: "EUR", target: money(60_000_000n, "EUR") })` |
| `employees.addContract(id, { salary: 5_400_000n, currency: "EUR" })` | `employees.addContract(id, { salary: money(5_400_000n, "EUR") })`             |
| `invoice.totals.total`, `invoice.balance`: `bigint`                  | `Money`; read `.amount` for the `bigint`                                      |
| board `totals: [{ currency, amount: bigint, weighted: bigint }]`     | `totals: [{ currency, amount: Money, weighted: Money }]`                      |

Breaking: an amount in another currency than its record returns an `invalid_request` error with hint `CURRENCY_MISMATCH` before any database call, and an unknown ISO 4217 code returns `CURRENCY_INVALID`. A deal, quote or invoice created without a `currency` takes it from its amounts. The SQL checks the same rule: the line-items setters refuse a line in another currency (`LINES_CURRENCY`), `update_deals` rejects an amount change in another currency (`DEAL_CURRENCY_MISMATCH`), and `record_invoice_payment` is now `(invoice, amount, currency, paid_at, method, reference)` and refuses a payment in another currency (`INVOICE_CURRENCY_MISMATCH`). The old five-argument function is dropped.

Breaking: the block SQL functions return every `int8` as text, and the clients read amounts only from an integer string or a `bigint`. Amounts past 2^53 now round-trip exactly, and a missing or malformed amount is an error instead of `0n`. Code that calls these functions through `$rpc` or `queryRaw` gets strings where it got numbers. Rerun `better-supabase sql sync` and generate a migration to install the new functions.
