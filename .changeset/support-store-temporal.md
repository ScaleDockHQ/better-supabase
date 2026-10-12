---
"better-supabase": patch
---

The support session store reads its time values with the definition's `temporal`: `createServer` passes it to `supportSessions(...).create` and on to the store through the new optional `SupportSessionStore.withTemporal`, and `sqlSupportStore(postgres, { schema, temporal })` takes an explicit namespace that wins over it, as block creators do.
