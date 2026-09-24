---
'better-supabase': minor
---

Generate types with `@supabase/postgrest-typegen` and build caching, live
queries and safety checks on the metadata it provides.

**Breaking changes**

- `gen` needs a database: a local connection, or the Management API for a
  project ref (`--project-ref`, `SUPABASE_ACCESS_TOKEN`). `database.types.ts`
  is now the `supabase gen types` output. The `types` config option is
  removed, and snapshots are version 2 (regenerate them).
- Doctor: BS101, BS102, BS104, BS105, BS201, BS202 and BS203 are retired.
  Supabase's advisors report those problems now, as BS100 (security) and
  BS200 (performance), through the Management API or a pinned, hash-checked
  splinter run locally.
- Jobs run on pgmq and pg_cron. Re-run `better-supabase sql add jobs`.
  `createJobs(source, queues)` no longer takes `worker`; `delay`, `lease`
  and `retryIn` are seconds; `Job` has `enqueuedAt`, `visibleUntil` and
  `lastError`. Over PostgREST, jobs use `pgmq_public` (no dedupe, schedules
  or lease extension).
- `/query` is built on `@tanstack/query-core` and invalidates by the tables
  a query read (`meta.bsTables`) instead of by key prefix.
- Writing a generated, identity or read-only view column fails with
  `invalid_request` before the request.

**New**

- `findUnique` by any unique key, typed constraint names and `isConflict`,
  `isCheck`, `isForeignKey`; `orThrow(factory)`; `codecs` config.
- Serializable query specs (`sb.spec`, `db.$run`, `InferResult`), cascade-aware
  invalidation, `sb.defineRpc(name, { invalidates })`, `next.cacheTags(spec)`.
- `skipToken`, offset infinite queries, `$rpc`, `$rpcMutation`, `$prefetch`.
- Live queries: `liveQuery`, `useLiveQuery` and the `realtime-tables` SQL
  module; doctor BS305 and BS306.
- `_count` includes, `db.$table(name)`, `db.$withoutPlugins()`.
- `better-supabase/plugins/rules` (runtime query rules with presets) and
  `better-supabase/lint` (ESLint and oxlint plugin); `sensitive` config.
- `jsonb-schemas` SQL module (pg_jsonschema check constraints from Standard
  JSON Schema); `supabase/config.toml` read through `@supabase/config` when
  installed.
