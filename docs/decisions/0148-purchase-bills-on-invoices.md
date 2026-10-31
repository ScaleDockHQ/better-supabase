# 0148: Keep purchase bills on the invoices table

- Status: accepted
- Date: 2026-10-30

## Context

Purchasing needs supplier bills, a three-way match against purchase orders and
receipts, requisitions before an order, incoming inspection and credit limits.
The `invoices` block already has lines, gapless numbering, payments, credit
notes, aging and accounting postings. Inventory already has purchase orders,
but receiving one wrote only stock movements, so nothing recorded which
quantities arrived together. Banking and collections (PRs 48 and 49) will pay
and collect both kinds of document.

## Decision

- **A direction column, not a second block.** `invoices.direction` is `sales`
  or `purchase`. The party columns name the supplier on a bill, and
  `supplier_reference`, `purchase_order_id` and `dimensions` are added, also to
  an adopted invoices table. Bills number per direction (`BILL-`, `BCN-`), and
  the unique number index covers `(tenant, direction, kind, number)`.
  `issue_invoice` books a bill.
- **Permissions by direction.** Every write on a bill needs
  `invoices.purchase` in place of the sales keys; reads stay on
  `invoices.read`.
- **Postings.** A bill books in the purchase journal: the supplier's payable
  against expense (carrying the bill's dimensions, so project costing counts a
  `project` dimension once) and `tax_receivable`. With inventory installed, a
  product line of a bill with a purchase order debits the payable the receipt
  booked instead of an expense, so received stock isn't counted twice. Paying a
  bill credits bank and debits the payable; the cash ledger code is per
  direction.
- **Three-way match in SQL.** `invoice_match_result` compares the product lines
  of a bill with its purchase order lines and the received quantities, across
  every issued bill of that order, within `options.matchTolerance`
  (`{ bps: 100, amount: 500 }`, the larger of the two). The worst line decides:
  `not_received`, `quantity_variance`, `price_variance` or `matched`.
  `record_invoice_payment` refuses an unmatched bill (`INVOICE_MATCH_FAILED`)
  unless the caller holds `invoices.override_match`. `purchase_bill_match`
  runs it for a reader and records `invoice.match_checked`.
- **Receipts are rows.** `receive_purchase_order` writes one
  `inventory_receipts` row with `inventory_receipt_lines`. With
  `receiptInspection` set to an inspections kind, the receipt schedules an
  inspection of that kind; the option names a kind, not a template, because
  templates are tenant rows the SQL can't check when it renders.
- **Requisitions on approvals.** `purchase_requisitions` are decided through
  an approval request when the approvals block is installed (subject
  `purchase_requisition`, default policy: a holder of `inventory.purchase`),
  and directly otherwise.
- **Credit limits from contacts.** `place_order` and `issue_invoice` (sales)
  compare open receivables plus the new total with the party's
  `credit_limit` in its `credit_currency`, unless the caller holds
  `orders.override_credit`.

## Alternatives considered

- **A separate `bills` block.** It would copy numbering, lines, payments,
  credits, aging and postings, and banking would have to reconcile against two
  tables.
- **Match on the bill's whole total.** Line-level results tell the user which
  item is off, and quantities must be checked per variant anyway.
- **A template key for incoming inspection.** Templates are tenant data, so a
  config key can't be validated when the SQL renders.

## Consequences

- An adopted invoices table gains four columns and a wider unique index on
  upgrade.
- A drop-ship receipt doesn't fulfil the sales order yet, and the order credit
  check reads the cart user's person in contacts only.
- Banking and collections build on one payable and receivable table and the
  same payment functions.
