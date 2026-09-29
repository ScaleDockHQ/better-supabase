---
'better-supabase': minor
---

Read replicas: set `SUPABASE_READ_URL` (or `readUrl`) and the server sends each request's reads to the replica and its writes to the primary. A successful write pins the request to the primary, and Next.js actions and routes set a `bs-primary-until` cookie so the next requests read their own writes for `replicas.pinMs` (5 s). `ctx.replica.pin()` pins after raw `$client`/`$sql` writes. `sb.connect(client, { executor })` runs queries through a custom executor while keeping `$client`.
