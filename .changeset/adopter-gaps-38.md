---
"better-supabase": minor
---

Adopter gaps, round 38: one-statement updates, a whole option matrix, finer keys for invoices and expenses, and confidential leave.

- Updates write the extra columns in the same `update` as the block's own columns: `save_product` (with `kind` and the price settings), `save_variant`, `save_category`, `update_expense`, `update_leave_request` and `save_calendar_event`. A table check across a block column and an extra column, such as `(kind = 'digital') = (delivery is not null)`, now holds when a product changes kind.
- Catalog: `setOptions(productId, options, { titleSeparator? })` (`set_product_options`) replaces a product's options by name and makes its variants the full matrix in one transaction. Variants of a surviving combination keep their id, duplicates and variants of removed values are deleted or archived, missing combinations get a new variant, and titles become the values joined by `" / "`. `options.maxVariants` (default 100) caps the matrix.
- Invoices: optional `permissions.create`, `update`, `issue`, `payment`, `credit` and `charge` (falling back to `write`) and `void`, `writeOff` and `reverse` (falling back to `manage`).
- Expenses without reports: optional `permissions.create`, `update`, `delete` (for someone else's expenses), `reimburse` and `categories`, each falling back to `manage`. `reimburse` also covers `reimburse_expense_report`, and `categories` the category functions with reports.
- Leave: `columns.types.confidential` maps a boolean column of your own types table. Leave of a confidential type is left out of `list`, `balances`, `ledger`, the feeds and the read policy for anyone but the employee, their manager and holders of `permissions.readConfidential` (`manage` when unset).
- Leave feed: `options.feed.names` reads first and last name when the employees block uses `name: "split"`, and `options.feed.typeKey` names the types column `hideTypes` matches, such as `category`.

Configs that set none of the new keys or columns behave as before.
