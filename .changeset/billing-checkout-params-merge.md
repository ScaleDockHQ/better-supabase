---
"better-supabase": patch
---

`billing.checkout` merges `params` deeply instead of shallowly: nested objects such as `metadata` and `subscription_data` merge with the block's, and arrays replace them. The customer, `client_reference_id` and the tenant's `metadata.organization_id` (on the session and, in subscription mode, on `subscription_data`) are set again after the merge, so app metadata no longer drops the link the Stripe webhook needs. `subscription_data` follows the final mode, including a `mode` set through `params`.
