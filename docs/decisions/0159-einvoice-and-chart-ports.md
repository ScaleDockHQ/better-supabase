# 0159: E-invoice and chart import ports

## Status

Accepted

## Context

`better-supabase/e-invoicing` writes UBL, but sending an invoice to an access
point and loading a reference chart such as RGS depend on providers and
national schemes that change faster than the library. Funding already has
`FundingClaimFormat` and `FundingClaimChannel`, so claims need nothing new.

## Decision

Add versioned ports with `apiVersion: 1` and no bundled implementation:
`EInvoiceFormat` and `EInvoiceChannel` with `sendEInvoice` in the invoices block,
and `AccountingChartFormat` with `importChart` in the accounting block. Both
return a `Result`, never throw for a failing adapter, and keep nothing: the app
stores the channel's `externalRef`. A chart is validated whole before any
account is saved.

## Consequences

Format and channel packages ship separately and need no new dependency here. A
breaking change to either port needs a new `apiVersion`.

ADR 0174 amends this: `sendEInvoice` keeps the channel's `externalRef` in
`invoice_deliveries` through the invoices client.
