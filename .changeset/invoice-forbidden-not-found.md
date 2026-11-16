---
"better-supabase": patch
---

Invoice actions (`record_invoice_payment`, `issue_invoice`, `update_invoice`, `delete_invoice`, `archive_invoice`, `restore_invoice`, `add_invoice_charge`, `credit_invoice` and `void_invoice`) now answer a caller who can read the invoice but lacks the action's key with `INVOICE_FORBIDDEN` (`42501`, a `forbidden` error) instead of `INVOICE_NOT_FOUND`. A caller who can't read the invoice still gets `INVOICE_NOT_FOUND`.
