---
"better-supabase": minor
---

`defineBucket` covers what Storage added in supabase-js 2.117, takes several path layouts and reports bad paths as a `Result`.

- `versioning` and `lifecycle`, applied with `bucket.apply(client)` and checked by doctor BS302. Connected buckets list `versions`, take a `versionId`, and have `removeVersions`, `purgeCache`, `copy` and `move`. `defineVectorBucket` and `defineAnalyticsBucket` declare the new bucket kinds.
- `path: [current, older]` accepts several templates, and `{...rest}` matches any depth. `defineBuckets({ ... })` registers definitions by id for rows that store a bucket id (`byId`, `resolve`, `connectStored`).
- Policies from `.sql()` use the name index, `sweep()` removes only objects matching every `within` value, and `replace()` checks `previous` against the tenant.
- **Breaking:** a bucket definition's `path(values)` returns a `Result<StoragePath>` instead of throwing.
- **Breaking:** a connected bucket's `publicUrl()` returns a `Result<string>`. `better-supabase codemod 0.6` lists both kinds of call.
