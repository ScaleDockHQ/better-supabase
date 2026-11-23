---
"better-supabase": minor
---

A `share: "tenant"` fill can call database functions. An authorization provider lists them in its new `sharedFunctions` field, by `schema.name`, with the tables each reads and the permissions those reads check, and `gen` writes them into the schema metadata. `bsb.kept` and `bsb.remote` take `functions: ["customer_payload"]`: the function's tables join the entry's tables and tags, its permissions join the share key, and inside the fill `$rpc` passes only the listed functions. Any other call still answers `SHARE_REFUSED`. Doctor BS430 fails a shared function that is security definer, isn't `language sql`, is volatile, reads the caller or reads a table its entry doesn't list, and `testAuthorizationProvider` checks that every table a shared function reads is shared per tenant. See ADR 1228.
