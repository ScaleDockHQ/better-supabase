---
"better-supabase": minor
---

Ledger and invoice gaps: organization purges with a ledger, the tenant column of block subjects, payments after a write-off, and actors on ledger and invoice payment reads.

- Data lifecycle: `purge_organization` now deletes a tenant's ledger entries and transactions. It sets the transaction-local `better_supabase.purge_tenant` setting, and the ledger's append-only guard lets a delete through only for the service role, only for that tenant and only while its deletion is due. Updates, and deletes by anyone else, still fail with `LEDGER_APPEND_ONLY`. Before, purging any organization with a ledger transaction failed.
- Subjects: the subjects blocks register (`ledger_account`, `work_item`, `product` and the others) name the tenant column `database.sql.tenantColumn` gives, as the block's tables do. Before, they kept `tenant_id`, so comments and other subject checks failed once such a block was installed.
- Invoices: `options.paymentsAfterWriteOff: true` lets a written-off invoice take payments, such as a provider payment that arrives after the write-off. The invoice stays `uncollectible` while a balance is left and moves to `paid` once nothing is owed. The default still refuses them with `INVOICE_NOT_PAYABLE`.
- Invoices: `payments(invoiceId)` (`list_invoice_payments`) reads an invoice's payments with `recordedBy`, and needs the read key.
- Ledger: `entries(accountId)` returns the transaction's `actorId` on each entry.
