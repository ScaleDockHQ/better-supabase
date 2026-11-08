# 0484: Ship bucket definitions to the browser from `better-supabase/storage/client`

- Status: accepted
- Date: 2026-11-08
- Amends: 0480, 0481

## Context

`defineBucket` from `better-supabase/storage` builds the bucket's paths, limits
and `connect`, and also its SQL, `config.toml`, drift report and `apply()`. The
example's `lib/buckets.ts` is imported by the browser client, so every data
route carried the policy builders (`policy.ts`, `core/access-sql.ts`) and the
SQL strings with it.

## Decision

- `better-supabase/storage/client` exports `defineBucket` without the server
  methods, plus the `connect` types, `TTL`, `parseSize`, `fromStorageError` and
  the image URL helpers. It is a runtime entry: it imports no Node built-ins.
- `createBucketBase` (`src/storage/client-bucket.ts`) holds everything both
  entries share. The server `defineBucket` builds the base and assigns `sql`,
  `toml`, `drift` and `apply` onto that same object, so `connect().bucket` is the
  bucket itself.
- `Bucket` extends the new `ClientBucket`. `connectBucket`, `AnyBucket`,
  `BucketClient.bucket`, the `.buckets()` registry and `deleteAccount` take a
  `ClientBucket`, so either entry's bucket works there. `better-supabase/storage`
  keeps every export and now also exports `ClientBucket`.
- `tests/next-build` fails when a route's first load contains the storage SQL
  or policy strings. `tests/storage/client` fails when the client entry's import
  graph reaches `bucket.ts`, `policy.ts`, `apply.ts` or `core/access-sql.ts`.

- `bsb.resolve` and `bsb.contextFromSession` in `better-supabase/next` wait for
  `io()` before the clock read that judges a token's expiry. A runtime prefetch
  render had cookies but no request, so the Flags SDK `identify` logged
  `Date.now()` prerender errors on `/[locale]` and `/[locale]/projects`. The
  core stays free of Next APIs; only the adapter entry imports `io`.
  `tests/next/prerender-clock.test.ts` holds the order.

## Measured

Raw bytes of first load on the example, before and after: `/customers` 1394664
to 1383710, `/assistant` 1298922 to 1287968, `/projects` 2002179 to 1991225.
Brotli drops 3.7 KB on each. `/login` does not change: it ships no data client.
The saving is smaller than the 28 KB the three modules weigh on their own,
because the connect code, the template parser and the error helpers that the
client needs stay in the bundle.

## Alternatives considered

- Marking `sql()` and `apply()` as lazy imports. Rejected: a bundler still
  includes a dynamically imported module in a chunk the page can request.
- A subpath without `defineBucket`, building handles from a generated registry.
  Rejected: the example and generated config already call `defineBucket`, so a
  second API would not be a drop-in.
