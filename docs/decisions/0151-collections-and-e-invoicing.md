# 0151: Collect on the ledger and write e-invoices as UBL without a validator

- Status: accepted
- Date: 2026-10-31

## Context

The invoices block takes payments one invoice at a time. Customers pay several
invoices with one transfer, and overpay or pay ahead, so the rest needs a
place to live. Overdue invoices need reminders with fees, and a dispute needs
to stop them. European buyers increasingly require structured e-invoices (EN
16931, sent over Peppol), and suppliers send them, so a bill should be read
from one.

## Decision

- **Party credit is a ledger account.** `record_party_payment` records each
  allocation through `record_invoice_payment` and posts the rest as
  `invoice.party_payment` from cash to `invoices:credit:<party>:<currency>`,
  one account per currency. The key `invoice-party-payment:<reference>` makes
  a replay a no-op. `apply_party_credit` posts `invoice.credit_applied` from
  the credit account to the invoice's receivable, so it shows as a payment
  with method `credit` and `reverse_invoice_payment` moves it back.
- **Books at payment time.** The party's remainder books in the bank journal
  (bank against the party's receivable) when it arrives; applying it books
  nothing, since the receivable was already credited.
- **Dunning is levels and three invoice columns.** `invoice_dunning_levels`
  (per tenant: level, days after due, template key, fee in minor units,
  final) and `dunning_level`, `dunning_at`, `dunning_paused_until` on the
  invoice. `run_invoice_dunning` (service role, the manifest's `dunning`
  schedule) moves each overdue invoice to the highest level it reached, adds
  the fee through `add_invoice_charge`, notifies the creator and records
  `invoice.dunning_escalated`. Notifications reach members only, so the
  customer's reminder is an outbox sink on that event using `templateKey`.
  `pause_invoice_dunning` needs a new `invoices.collect` key.
- **Recurring invoices stay a templates recipe.** A template type's `apply`
  already creates an invoice and template schedules (0128) run it, so no
  `invoice` template target is added.
- **`better-supabase/e-invoicing` is pure.** `toUbl` writes UBL 2.1 per EN
  16931 and Peppol BIS Billing 3.0 from an issued invoice, with VAT counted
  per category and rate and the difference to the block's per-line tax in the
  rounding amount, so the payable amount is the invoice's total. It refuses
  tax-inclusive prices. `fromUbl` reads a document into purchase bill input,
  loading `fast-xml-parser` lazily as an optional peer. `EInvoiceChannel`
  (`apiVersion: 1`) is the port to an access point; none is bundled. UBL 2.1,
  EN 16931-1:2017 and Peppol BIS Billing 3.0 are pinned in `SPEC_PINS`.

## Alternatives considered

- **Unapplied payments as rows.** A table of unallocated amounts would hold a
  balance outside the ledger, which ADR 0080 rules out.
- **Bundling the Peppol Schematron.** The rules are XSLT 2.0 and change with
  each Peppol release; validators at access points already run them. The docs
  name the official artefacts instead.
- **A hand-written XML reader.** Reading arbitrary UBL needs namespaces,
  entities and attributes, which a maintained parser handles; it stays an
  optional peer so `toUbl` alone pulls nothing in.

## Consequences

- An app that collects payments in bulk calls one function and keeps the
  remainder without its own table.
- Dunning fees appear as charges, so they raise the balance and the aging, and
  they are not in the original e-invoice.
- Apps send e-invoices through their own access point and validate there.
