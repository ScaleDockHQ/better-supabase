---
"better-supabase": patch
---

A quote's lines carry `taxCodeId`, `unitCost`, `discountAmount`, `costSource`, `locationId`, `binId` and the billing party columns when the line table has them, so a published version keeps them and accepting a quote with unpublished changes no longer blanks them on the restored lines. The customer's views (`public_quote`, `portal_quote`) leave the cost, stock and billing keys out. Run `better-supabase upgrade` to regenerate the quotes module.
