---
"better-supabase": minor
---

Two batch reads for approval sweeps and bill lists. `invoices.approvalStatuses(invoiceIds)` (`purchase_invoice_approval_statuses(invoice_ids uuid[])`) returns where each purchase invoice stands in approval as a map keyed by invoice id, and `approvals.getMany(ids)` (`get_approvals(request_ids uuid[])`) returns requests with their decisions and items in the order asked. Both skip an id the caller cannot read instead of failing the batch.
