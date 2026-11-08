---
"better-supabase": minor
---

Add `better-supabase/storage/client`: `defineBucket` without the SQL, `config.toml`, drift and admin code, for bundles that ship to the browser. `better-supabase/storage` is unchanged, and its `Bucket` is now an extension of the new exported `ClientBucket` type, which `defineBuckets`, `.buckets()` and `deleteAccount` accept. In the Next.js example, importing the client entry removes about 11 KB raw from every data route's first load.

`next` adapters now wait for `io()` before they read the clock in `bsb.resolve` and `bsb.contextFromSession`, so a Next.js runtime prefetch render no longer logs `Date.now()` prerender errors when the flags adapter or another caller resolves a request with cookies. A prerender never judges token expiry; the check runs when the request does.
