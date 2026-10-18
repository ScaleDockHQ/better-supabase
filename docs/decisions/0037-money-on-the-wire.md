# 0037: Send every amount as Money and every int8 as text

- Status: accepted
- Date: 2026-10-17

## Context

ADR 0024 keeps money in `bigint` minor units, but only the commerce blocks
(catalog, orders) followed it. The sales blocks (deals, quotes, invoices,
pipelines) and the employee contracts returned a bare `bigint` next to a
separate `currency` field, so a caller could add a EUR total to a USD one
without an error.

The values also lost precision on the way. A block SQL function returns its
row as `jsonb`, and `jsonb` writes an `int8` as a JSON number. PostgREST and
`JSON.parse` read that number as a JavaScript `number`, which is exact only
up to 2^53. The decoders then accepted a `number`, a numeric string or a
missing value, and turned a missing value into `0n`. A corrupted or missing
amount looked like a real zero.

## Decision

Every amount that has a currency is a `Money` value (`{ amount: bigint,
currency }` from `better-supabase/commerce`) in the public types of the
deals, quotes, invoices, pipelines, employees, catalog and orders blocks.
The separate `currency` input field is gone where `Money` carries it: a
contract's `salary` is `Money`, a deal's `amount` is `Money`. Counts and
goals without a currency (target goals and progress, document numbers) stay
`bigint`.

Every `int8` a block SQL function returns is text. The row builders cast
these columns with `int8Text` (`src/sql/money-sql.ts`), and aggregates cast
with `::text`. The decoders in `src/core/block-helpers.ts` (`bigintOf`,
`optionalBigintOf`) and `src/blocks/money-codec.ts` (`moneyOf`,
`optionalMoneyOf`) accept only a string matching `^-?\d+$` or a `bigint`. A
required value that is missing, a JSON number or a decimal string is an
error, never `0n`. `money()` checks the currency against ISO 4217, so a row
with an unknown code is an error too.

Inputs go to SQL as `amount.toString()` with their currency. Before any
database call, the client returns a `Result` error with kind
`invalid_request` when the amounts don't share the record's currency (hint
`CURRENCY_MISMATCH`) or the currency isn't an ISO 4217 code (hint
`CURRENCY_INVALID`). The SQL checks the same rule for callers that skip the
client: the line-items setter refuses a line in another currency
(`LINES_CURRENCY`), and `record_invoice_payment` takes the payment's
currency and refuses a different one (`INVOICE_CURRENCY_MISMATCH`).

## Alternatives considered

Keeping `bigint` amounts with a separate `currency` field and only fixing
the wire format. It fixes precision but keeps the mixed-currency bug, and
every caller has to pair two fields by hand.

Returning amounts as JSON numbers and parsing them with a reviver that
reads big integers. `JSON.parse` has already rounded the number by the time
a reviver sees it, unless the runtime supports the source text access
proposal, which not every WinterTC runtime does (invariant 6).

Returning `numeric` instead of `int8`. `jsonb` writes `numeric` as a JSON
number as well, so it has the same 2^53 problem.

Decoding a missing amount as `0n`, as before. It hides a broken query or a
dropped column as a real zero, which in an invoice balance is worse than an
error.

## Consequences

Amounts past 2^53 round-trip exactly, and adding amounts in two currencies
fails with `CurrencyMismatchError` instead of returning a wrong sum. This
is a breaking change for every caller of the sales and employees blocks,
listed in the changeset with an old-to-new table, and it needs a migration
for the new `record_invoice_payment` signature and the line-items check.

Pipeline totals decode each currency with `money()`, so a deal stored with a
code outside ISO 4217 makes the board fail instead of showing that total.
Apps that store such codes have to fix the rows first.

`$rpc` and the generated types still see a function's `int8` result as a
`number`; the doctor's BS223 warns about scalar `int8` and `numeric`
function results so apps can apply the same rule to their own functions.
