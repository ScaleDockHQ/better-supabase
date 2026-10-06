---
"better-supabase": minor
---

`defineBucket` covers what Storage added in supabase-js 2.117:

- `versioning` and `lifecycle` (noncurrent version expiration), set through the Storage API by the new `bucket.apply(client)`, which also creates or updates the bucket. `better-supabase doctor` (BS302) compares both with `storage.buckets`, and the config's `buckets` take them.
- On a connected bucket, `versions(target)` lists an object's versions, `download`, `signedUrl`, `publicUrl` and `copy`/`move` take a `versionId`, and `removeVersions(target, ids)` deletes versions.
- `cacheNonce` on the URL methods, and `purgeCache(target)` for the CDN.
- `defineVectorBucket` declares a vector bucket and its indexes, creates them with `apply()`, and puts, queries, gets and removes vectors with a dimension check. `defineAnalyticsBucket` creates an analytics bucket and returns its Iceberg catalog.

Storage's `FeatureNotEnabled` errors and missing routes now map to `unsupported`.
