---
"better-supabase": patch
---

`blocks.<module>.api` now always writes a wrapper for every function the block's TypeScript client calls over a transport, also when `api.functions` lists fewer. With `"rate-limit": { api: { schema: "api", functions: ["check_rate_limit"] } }`, `checkAll` over `rpcTransport(admin, { schema: "api" })` failed with PGRST202 because `api.check_rate_limits` was missing; the module now writes it and `api.purge_rate_limits`, with the same `security invoker` body and `service_role` grant as `api.check_rate_limit`. Run `better-supabase add` or `upgrade` to rewrite the module files.
