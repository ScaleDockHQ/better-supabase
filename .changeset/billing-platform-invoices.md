---
"better-supabase": minor
---

Platform staff read invoices across tenants. `billing.allInvoices({ status, limit, before })` lists every tenant's Sync Engine invoices, newest first, as `{ organizationId, customerId, row }` (`billing_all_invoices`), and the per-tenant `invoices`, `paymentMethods` and `customerDetails` reads also answer platform staff with the billing module's `viewAll` permission.
