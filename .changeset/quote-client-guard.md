---
"better-supabase": patch
---

A quote row written directly through the Data API can no longer plant the public link token or a customer decision: an insert outside an import or the service role clears them. `variantOf` must name a quote of the same organization (`QUOTE_VARIANT_TENANT`), so the variant functions can't be pointed at another organization's quote. Run `better-supabase upgrade` to regenerate the quotes module.
