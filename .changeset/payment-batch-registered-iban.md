---
"better-supabase": patch
---

With the contacts block installed, `create_payment_batch` pays a supplier that has a registered bank account only to one of its registered IBANs. Leave `iban` out to pay the primary account; an IBAN the supplier didn't register fails with `PAYMENT_BATCH_CREDITOR_INVALID`, so the caller can no longer redirect a payment to an account of their choice. Run `better-supabase upgrade` to regenerate the banking module.
