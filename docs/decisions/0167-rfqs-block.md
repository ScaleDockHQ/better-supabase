# 0167: Requests for quotation award one supplier quote into a purchase order

- Status: accepted
- Date: 2026-10-31

## Context

A buyer often asks several suppliers for a price on the same lines before
ordering. `contacts` already holds suppliers with roles and a status, and
`inventory` already holds purchase orders. Nothing recorded the request, the
answers or the choice between them.

## Decision

`rfqs` is a block (`better-supabase/blocks/rfqs`) with five tables: `rfqs`,
`rfq_lines`, `rfq_suppliers`, `rfq_quotes` and `rfq_quote_lines`. All are
adoptable (ADR 0098).

- A request is `draft`, `open`, `closed`, `awarded` or `cancelled`. It opens
  only with a line and a supplier, takes quotes only while open, and an awarded
  request is final.
- A supplier is a party type and id, as in `contacts`. When contacts is
  installed the party must hold the `supplier` role (or no role) and must not be
  blocked.
- A supplier has one quote per invitation. Quoting again replaces the prices and
  raises `revision`, so history is the audit log and not a second table. The
  total is stored in minor units (ADR 0037).
- `compare_rfq` ranks live quotes by total among those that price every line and
  marks the best unit price per line.
- `award_rfq` needs a quote that prices every line. It marks the others
  `rejected` and, given a location with inventory installed, calls
  `save_purchase_order` at the quoted unit prices and stores the order id.
  Every line then needs a variant.
- The permission keys are `rfqs.read`, `rfqs.write` and `rfqs.manage`.

## Alternatives considered

- Keeping every quote revision as a row: rejected, since the audit log has the
  history and the comparison needs one live price per supplier.
- Awarding per line to several suppliers: rejected for now. One award is one
  purchase order; a split is two requests.
- Writing the purchase order inside `rfqs`: rejected, since `inventory` owns
  its numbering, receiving and approvals.

## Consequences

Buyers get a traceable choice between suppliers with no change to purchase
orders. A split award needs two requests. Without inventory the award records the
choice and leaves ordering to the app.
