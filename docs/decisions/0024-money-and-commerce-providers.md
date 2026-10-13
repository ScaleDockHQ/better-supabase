# 0024: Keep money in bigint minor units behind versioned commerce providers

- Status: accepted
- Date: 2026-10-13

## Context

The commerce blocks (catalog, inventory, orders, promotions) all handle
prices, and they need to take payments and charge sales tax. A JavaScript
`number` can't hold 0.10 exactly, so sums and tax drift by a cent. The
number of decimals also differs per currency: two for `EUR`, none for `JPY`,
three for `KWD`. Payment and tax services differ per app (Stripe, Adyen,
Mollie, a tax engine, fixed VAT rates), and invariant 10 asks for a
versioned contract wherever a third party plugs in. ADR 0009 already makes
`stripe` an optional peer loaded lazily.

## Decision

`better-supabase/blocks/commerce` holds money as
`{ amount: bigint, currency }`, where `amount` counts the currency's minor
units. The minor units come from ISO 4217 List One, vendored in
`tests/standards/schemas/iso-4217-list-one-2026-09-17.xml`, copied into
`src/blocks/commerce/iso4217.ts` and pinned as `SPEC_PINS.iso4217`; the
standards test checks the table against the XML. Arithmetic refuses mixed
currencies, and rates are decimal strings applied with half-to-even
rounding. JSON carries the amount as a string.

Payments and tax are two extension interfaces with `apiVersion: 1`:
`PaymentProvider` (`createPayment`, `capture`, `refund`, `parseWebhook`, and
optionally `cancel` and `get`) and `TaxProvider` (`quote`, `commit`,
`reverse`). Both return a `Result` and take an idempotency key. Their
conformance kits are `testPaymentProvider` and `testTaxProvider` in
`better-supabase/testing`. The first adapters are `stripePayments`
(PaymentIntents), `stripeTax` (Stripe Tax calculations and transactions)
and `fixedRates`. The Stripe adapters type the client structurally and load
`stripe` through `lazyStripe`, as billing does. Stripe's own amount units
(`ISK`, `UGX`, `MGA`, and multiples of 10 for three-decimal currencies) are
converted in `toStripeAmount` and refused when inexact. The subpath has no
SQL; the money columns arrive with the catalog and orders modules.

## Alternatives considered

A decimal library (`decimal.js`, `dinero.js`) would add a runtime
dependency, which invariant 1 rules out, and its values don't survive
`structuredClone` or a Server Component boundary as plain data. Integer
`number` minor units overflow past 2^53 for high-inflation currencies and
invite float math. Calling Stripe from the blocks directly would tie every
commerce block to one provider. Taking the decimals from
`Intl.NumberFormat` would vary by runtime and ICU version.

## Consequences

Amounts are exact, and the same code runs on every WinterTC runtime.
Callers write `1999n` or `parseMoney("19.99", "EUR")` instead of `19.99`,
and `bigint` needs `moneyToJson` before `JSON.stringify`. A new ISO 4217
list means a new vendored file, its SHA-256 in `SOURCES.md` and a new pin.
Another payment or tax service ships its own adapter against the kits. A
breaking change to either contract needs `apiVersion: 2`.
