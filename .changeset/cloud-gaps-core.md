---
"better-supabase": minor
---

Closes the gaps found on 0.9.0: `audit()` takes `tenant_path` and `tenant_function`, `admin({}, { as })` names the acting member, optional RPC arguments accept `undefined`, `createHono` and `createNext` share one server, OAuth server resources follow RFC 8707, `jwtType` validates `typ`, billing webhooks cover subscriptions, usage meters count distinct or computed values, and the doctor flags partitions without RLS (BS343).
