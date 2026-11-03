# 0206: E-invoice tables and hints follow the convention, with one documented prefix

- Status: accepted
- Date: 2026-11-02
- Amends: 0130, 0182

## Context

ADR 0130 names a table after its entity and writes hint codes in words
separated by underscores. The delivery log was `invoice_e_deliveries` and its
hints started with `EINVOICE_`, while its functions were already
`record_e_invoice_delivery` and `list_e_invoice_deliveries`. The Peppol
participant table is `invoice_e_endpoints`, with the functions
`set_invoice_e_endpoint` and `invoice_e_endpoints`.

## Decision

- The delivery log is `e_invoice_deliveries`, its indexes and read policy start
  with that name, and the hints are `E_INVOICE_*`. The invoices module moves to
  version 3: its name migration renames the table with its indexes and
  policies, and the changeset lists the hint codes.
- The participant table, `set_invoice_e_endpoint` and `invoice_e_endpoints` keep
  their names. The participant id belongs to the invoices block (it is read to
  address an invoice), so the `invoice_` prefix is the entity prefix and
  `e_endpoint` is its noun. Renaming it would also rename two public client
  functions for no change in what they do. This is the one exception to 0130 in
  the invoices block.

## Consequences

An install on version 2 renames the delivery table on its next `upgrade`. Code
that matched the `EINVOICE_*` hints has to match `E_INVOICE_*`.
