---
"better-supabase": minor
---

Two versioned ports (`apiVersion: 1`) with no bundled implementation.

- `better-supabase/blocks/invoices` adds `EInvoiceFormat`, `EInvoiceChannel` and `sendEInvoice`, which renders an issued invoice and sends it through your access point. Drafts and void invoices are refused with `EINVOICE_NOT_ISSUED`.
- `better-supabase/blocks/accounting` adds `AccountingChartFormat` and `importChart`, which saves a reference scheme's chart (such as RGS) parents first and maps its roles. An invalid chart saves nothing (`ACCOUNTING_CHART_INVALID`).

No migration is needed.
