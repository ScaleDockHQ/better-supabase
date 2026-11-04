---
"better-supabase": minor
---

`endSessions`, `lastSignIns` and `suspendAccount` accept a `BlockTransport` besides a `SqlClient`, and
the sessions module gains `better_supabase.end_sessions(p_user)`. `server.endSessions` and
`server.suspendAccount` use the service role's Data API when `postgres` is not configured, and
`server.lastSignIns` is new. `gen` adds the block API schemas that `schemas` does not list to
`database.types.ts` (turn it off with `gen.api.types: false`), so `client.schema("api").rpc(...)` is
typed. `blockSet.serviceBlocks(admin)` builds the block clients over one `rpcTransport`, calling the
API schema each generated entry names.
