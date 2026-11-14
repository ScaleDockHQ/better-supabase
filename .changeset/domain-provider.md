---
"better-supabase": minor
---

The domains block takes a hosting platform. `createDomainsAdmin({ provider })` accepts a versioned `DomainProvider` (`add`, `verify`, `remove`, `status`) and gains `add({ hostnameId })`, `remove({ hostname })` and `status({ hostnameId })`. With a provider, `verify` asks the platform after the TXT check passes and fails with `DOMAIN_PROVIDER_UNVERIFIED` until it agrees; without one, it behaves as before. `vercelDomainProvider(new Vercel({ bearerToken }), { projectId, teamId })` implements it over `@vercel/sdk`, an optional peer, and `testDomainProvider` in `better-supabase/testing` checks your own.
