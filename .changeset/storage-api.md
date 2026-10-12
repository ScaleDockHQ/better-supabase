---
"better-supabase": minor
---

`bucket.connect()` and `buckets.connectStored()` take any `StorageApi`, not only a supabase-js client: `StorageClient` is now `StorageApi | { storage: StorageApi }`, where `StorageApi` is an object whose `from(bucket)` returns a `StorageBucketApi`, the file methods of `supabase.storage.from(bucket)` typed structurally with the supabase-js `{ data, error }` results. A supabase-js client and its `storage` still type-check unchanged. `bucket.apply()`, `defineAnalyticsBucket().connect()` and `defineVectorBucket().connect()` call the admin API, so they take the new `StorageAdminClient` (a supabase-js client) instead.
