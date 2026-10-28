---
"better-supabase": minor
---

Adopter gaps, round 39: variant status, category keys, expense categories without a key or currency, reapproval of changed leave, and draft invoice edits and deletes.

- Catalog: `setVariantStatus(variantId, status)` (`set_variant_status`) moves a variant to `active`, `archived` or a label `values.variants.status` names, with the update key. It needs a mapped `columns.variants.status` and refuses without one (`CATALOG_VARIANT_STATUS_UNSUPPORTED`). A variant that goes live again needs a free combination of option values.
- Catalog: optional `permissions.categoryCreate`, `categoryUpdate` and `categoryDelete` for `save_category`, `move_category` and `delete_category`, each falling back to `manage`.
- Expenses: the categories table's `key` and `currency` columns may map to `null`. Without a key, a category's key is its id, and the ledger names its account by the id. `options.categoryExtraColumns` adds columns that `saveCategory({ fields })` writes and category reads return under `fields`.
- Expenses without reports no longer register the ledger's `ledger_account` subject, so comments, messaging, hiring and search render without the ledger tables.
- Leave: `options.reapprove: true` lets the requester change their own approved leave, which goes back to approval: the taken leave returns to the balance and a new approval opens. `permissions.reapprove` names a key whose holders may change anyone's leave the same way.
- Invoices: `update(invoiceId, patch)` (`update_invoice`) changes a draft's header and extra columns in one statement with the `update` key, and `delete(invoiceId)` (`delete_invoice`) deletes a draft with its lines and charges, with the new optional `delete` key (falling back to `update`, then `write`). Both refuse an issued invoice and record `invoice.updated` and `invoice.deleted`.

Configs that set none of the new keys, columns or options behave as before.
