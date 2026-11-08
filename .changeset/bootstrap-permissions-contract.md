---
"better-supabase": minor
---

The sessions bootstrap returns the caller's permissions when the authorization provider sets `functions.bootstrapPermissions`. The value is a versioned (`apiVersion: 1`), provider-neutral contract with a full form (keys per tenant) and a compact form (a key index and one bitset per tenant), read into `Bootstrap.permissions`; another `apiVersion` or a damaged value gives `null`. `compactBootstrapPermissions` and `expandBootstrapPermissions` come from `better-supabase/server`, and the types from `better-supabase/contract`. At 150 tenants and 300 keys the compact form is 21,314 bytes against 737,192. `permissions: false` on a bootstrap entry leaves them out. `better-supabase upgrade` rewrites the `sessions` module only for an app whose provider sets the template; no data migration is needed.
