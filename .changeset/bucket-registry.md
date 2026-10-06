---
"better-supabase": minor
---

`defineBuckets({ ... })` from `better-supabase/storage` registers bucket definitions by id, for rows that store a bucket id next to an object path. `byId(id)` returns the definition, `resolve({ bucket, path })` also checks the path against that bucket's templates, and `connectStored(client, { bucket, path }, options)` connects the bucket and checks the path with the client, tenant included. An unknown id or a path outside the templates is an `invalid_input` error, never a fallback bucket, and two buckets with one id throw when the registry is defined. Replace an app-side map from bucket id to definition with the registry.
