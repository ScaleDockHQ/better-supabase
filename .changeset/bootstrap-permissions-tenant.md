---
"better-supabase": minor
---

Breaking: a sessions bootstrap wrapper returns the authorization provider's permissions only for a call that names a tenant. A call without a tenant, such as a shell bootstrap, gets `permissions: null` instead of one permission bitset per tenant the caller belongs to, which every cache miss paid for and most pages never read. Set `permissions: "all"` on a bootstrap entry to keep the old behavior, or pass the page's tenant to `bsb.bootstrap({ rpc, tenant })`. `permissions: false` still leaves them out. Run `better-supabase upgrade` and generate a migration to rewrite the wrappers.
