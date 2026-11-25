# CentraKit performance review: what changed and what is measured

Each row names the item, what shipped, and the evidence. "Not measured" means
the code and unit tests are in, and the number needs a live stack, a Vercel
preview or CentraKit itself.

| Item                        | Shipped                                                                                                                                                                                       | Evidence                                                                                                                                                                                                                                                                                                                        |
| --------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1. Request stats            | `connect(supabase, { claims })`, `connect({ executor, storage })` and the `contextFromSession` client report to the request recorder. Phases, `decodes` and a JSON stats route with a reason. | Unit tests. Parity with `pg_stat_statements` on `tests/validation-centrakit`: not measured (the project has no runner for it yet).                                                                                                                                                                                              |
| 2. BS428                    | Matches a policy as Postgres stores it.                                                                                                                                                       | Unit tests. The dry run on CentraKit: not run.                                                                                                                                                                                                                                                                                  |
| 3. Kept reads               | `cached({ keep })`, `bootstrap({ kept })`.                                                                                                                                                    | 29 parallel renders do one database call, a restarted instance on the same store does none (`tests/next/cached-keep.test.ts`). `tests/cache.spec.ts` (hard load 2 calls, restart 0 or 1 over seven routes) and the three over-budget detail routes: not run. Only `getCustomer` and `getCustomers` carry `keep` in the example. |
| 4. Tags                     | `bsb.expireTags`, BS648, the `expire-tags` codemod (reports, does not rewrite), `tagCalls` and `expiredTags` counts.                                                                          | Unit and cross-instance tests.                                                                                                                                                                                                                                                                                                  |
| 5. Actions                  | `keptHits` per phase in stats and the `bsb.action` log line, BS649, the example's refresh caller.                                                                                             | Unit tests.                                                                                                                                                                                                                                                                                                                     |
| 6. Proxy                    | `createProxy({ auth, env, jwks, debug })` without the definition, `proxy-permissions.generated.ts`, BS650 and a size ceiling in `tests/next-build`.                                           | Unit tests. Proxy size: see below.                                                                                                                                                                                                                                                                                              |
| 7. Release                  | 0.86.0 shipped (PR 1159).                                                                                                                                                                     | The tag probe is for the maintainer to run.                                                                                                                                                                                                                                                                                     |
| 8. Doctor on large projects | Done.                                                                                                                                                                                         | Unit tests.                                                                                                                                                                                                                                                                                                                     |
| 9. Authz subscribe          | Idle join, one channel per client, topic and event, no catch-up RPC on the first join with `liveVersion`.                                                                                     | Unit tests. The four statements under `pg_stat_statements`: not measured. The example does not pass `liveVersion` yet.                                                                                                                                                                                                          |

## Proxy size

`tests/next-build/server-baseline.json` held the proxy at 854,641 bytes raw
before this work. After the instance-free `createProxy`, the compiled example
measures 716,096 bytes (about 16 percent less). The 400 KB goal is not met:
Next's own runtime is about 510 KB of that bundle, so the size test holds the
measured ceiling (720 KB) instead. BS650 reads `.nft.json` and is info level
because the traced-file total has not been checked against a real project.

The server baseline now records 716,096.

The example keeps its own permission catalog (it adds legacy keys), so its hash
differs from the generated `proxyPermissions`. Its proxy still builds the
catalog from `lib/permission-catalog`.

## Known limits

- `bootstrap({ kept })` can serve an ended session for up to `life.revalidate`
  seconds (default 30) unless `bsb.evictSession` runs.
- Batches (`$many`) and `$rpc` calls are not kept.
- The proxy's own token decodes are not counted in `decodes`.

## Maintainer steps

1. Apply the migrations from the release.
2. Set `BSB_KEPT_STORE=vercel` in the three Vercel environments.
3. Run the probe against a preview and fill the "pending maintainer run" rows
   in `(integrations)/vercel/cache.mdx` and the 0.84 to 0.85 guide:

   ```sh
   BSB_TAG_PROBE_SECRET=... node scripts/probe-vercel-tags.ts https://<preview>.vercel.app --second
   ```

4. Run the dry run on CentraKit for BS428 and `tests/cache.spec.ts`
   against the live stack.
