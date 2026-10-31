---
"better-supabase": minor
---

The `erp` preset now installs `accounting`, `banking` and `approvals`, so sales invoices, purchase bills, payments, stock movements, expense reports and depreciation book into the journals, bank statements reconcile against the ledger, and purchase requisitions go through approvals. Each organization runs `db.accounting.setup(organizationId)` once before anything books. A project on `preset: "erp"` gets the new blocks on its next `better-supabase upgrade`; generate a migration after it.

Add the `manufacturing` preset: `erp` plus `manufacturing`, `inspections`, `cases` and `qualifications`. It sets `purchaseSuggestions: "requisition"` on manufacturing, so material requirements raise purchase requisitions, and `receiptInspection: "inspection"` on inventory, so every receipt of a purchase order schedules an incoming inspection. `init --preset manufacturing` and `add --preset manufacturing` accept it, and both presets have a docs page that describes the postings, the three-way match and the bank reconciliation.
