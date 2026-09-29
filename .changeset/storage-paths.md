---
'better-supabase': minor
---

Storage paths and image URLs. `StoragePath<'bucket-id'>` brands paths from `bucket.path()` and `upload()`, and bucket clients reject paths of other buckets. The `storagePaths` config types text columns as `StoragePath` in generated rows (zod and valibot schemas follow). New `better-supabase/next/image` subpath: `createImageLoader({ url })` is a `next/image` `loaderFile` that serves public objects through Storage image transformations. New `storagePathColumns` query rule (in `recommended()` and `strict()`) flags Storage URLs and bucket paths written to `*_url` columns. `renderUrl` is covered against `/render/image/public` and `/render/image/sign`.
