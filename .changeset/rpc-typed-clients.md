---
"better-supabase": patch
---

`rpcTransport` and the jobs block's `pgmq_public` backend accept a typed `SupabaseClient<Database>` without a cast. `RpcClient` and `QueueRpcClient` now declare `never` parameters, so a client whose `schema` and `rpc` only take the names its `Database` lists (which leave out the block schemas) fits; the calls themselves are unchanged.
