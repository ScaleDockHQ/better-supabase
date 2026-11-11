---
"better-supabase": patch
---

`AuthzSubjectSeed` has a `tenant` field: the tenant a bootstrap subject is restricted to by the provider's `subjectForTenant`, or `null` for the whole subject. `accessFor` sets it from the new `Bootstrap.subjectTenant`, which the bootstrap wrapper reports as `subject_tenant` (run `bsb upgrade` to regenerate it). An authorizer that caches the seed by user and version must key it by the tenant, and `testAuthorizer` checks that a seed for another tenant is ignored.
