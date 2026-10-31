---
"better-supabase": minor
---

Add the `banking` block (`better-supabase/blocks/banking`): bank accounts, statements and
transactions with reconciliation. `parseCamt053` reads camt.053.001.02 and .08 (with the optional
`fast-xml-parser` peer) and `parseMt940` reads MT940. Importing a statement twice adds nothing.
`suggestMatches` ranks open invoices by RF creditor reference (ISO 11649), Dutch
betalingskenmerk, invoice number in the remittance, amount and counterparty IBAN, and `match`
records the invoice payment. Bank rules match transactions by a filter tree and book them in the
bank account's journal or ignore them, and `reconciliation` compares the statement balance with
the books. Bank feeds plug in through the versioned `BankFeed` port; none is bundled. The
permissions are `banking.read`, `banking.import`, `banking.reconcile` and `banking.manage`. ADR
0153 explains the design.
