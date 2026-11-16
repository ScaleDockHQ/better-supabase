---
"better-supabase": patch
---

Invoice actions (`record_invoice_payment`, `issue_invoice`, `update_invoice`, `set_invoice_lines`, `delete_invoice`, `archive_invoice`, `restore_invoice`, `add_invoice_charge`, `credit_invoice`, `void_invoice` and `write_off_invoice`) now answer a caller who can read the invoice but lacks the action's key with `INVOICE_FORBIDDEN` (`42501`, a `forbidden` error) instead of `INVOICE_NOT_FOUND`. A caller who can't read the invoice still gets `INVOICE_NOT_FOUND`, now with the message "no such invoice you can read" (it was "no such invoice you can edit", "delete" or "manage"); match on the hint, not the message. The permission check runs before the row lock, so a caller without access locks nothing.
