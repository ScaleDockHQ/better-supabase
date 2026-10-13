# 002: Audit findings triage

Status: DONE on `fix/audit-triage`.

The audit of 2026-10-12 reported findings in bugs, security, performance, tooling, docs, debt and direction. Each one was re-verified against the code before it was planned. This file records the verdicts, what landed, and what was left in place on purpose, so the next audit does not raise them again.

## Fixed

| Finding        | Change                                                                                                                                                           | Changeset                           |
| -------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------- |
| BUG-01         | A counted read runs its rows and count queries in one transaction in `executeOn`, so both see one snapshot.                                                      | `postgres-counted-read-snapshot`    |
| DIR-1, PERF-03 | `SessionOptions.statementTimeout`, admin transactions with a timeout and no claims, and a bare admin `queryRaw` without `begin`/`commit` when no timeout is set. | `postgres-session-timeout`          |
| PERF-01, DIR-2 | A per-executor rpc signature cache (misses are not cached, entries are evicted on `42883`, `42P13` and `42804`); OUT and TABLE arguments are dropped.            | `postgres-rpc-signatures`           |
| DIR-3 (partly) | `otel()` wraps `executor.batch` in a `BATCH` span.                                                                                                               | `otel-batch-span`                   |
| BUG-02         | Webhook retries use equal jitter with a 1 s floor, so a retry never fires immediately and the 5 s, 5 m, 30 m schedule holds.                                     | `webhooks-equal-jitter`             |
| SEC-01         | `env` writes its file with mode `0600`, and fixes the mode of an existing file even when the contents are unchanged.                                             | `cli-env-file-mode`                 |
| SEC-02         | `clientIp` reads the last `x-forwarded-for` hop, the one the app's own edge appended, matching the SQL modules.                                                  | `auth-client-ip-last-hop`           |
| DEP-01         | `@types/node` pinned to the Node 24 line.                                                                                                                        | `node-types-24`                     |
| DX-02, DOC-01  | `docs/agents/tooling.md` describes `pnpm check`; the root `README.md` lists the six missing subpaths and the current OpenAPI versions.                           | none                                |
| DEBT-1         | `lockTable` and `revokeTable` in `src/sql/shared.ts` replace the drifted local helpers and the inline revokes; function grants reuse `userGrant`/`serviceGrant`. | none (golden SQL byte-identical)    |
| DEBT-2         | `raise` takes an optional hint; 194 hand-rolled sites now use `raise` or `fail`.                                                                                 | none (golden SQL byte-identical)    |
| DEBT-3         | `buildModel` and spec `build` are split into one function per step (`model-types.ts`, `model-relations.ts`, `model-functions.ts`, `spec/build-resource.ts`).     | none (fixtures and specs unchanged) |
| DIR-4          | `defineFunction` keeps a descriptor under `Symbol.for("better-supabase.function")`; `functionRoute()` in `better-supabase/spec` documents it.                    | `spec-function-route`               |

`tests/sql/render-golden.test.ts` renders every SQL module in every mode that changes its output and was committed before DEBT-1 and DEBT-2. Both refactors left every file under `tests/sql/__golden__` byte-identical, so doctor and the module checksums see no drift in installed apps.

## Rejected

1. **BUG-03, the null count in chunked writes.** Only inserts are chunked, and every insert plan returns a numeric count, so the null-to-0 coercion is never reached.
2. **DX-01, `needs: verify` in CI.** `verify` is a job in the same `ci.yml` that calls the reusable workflow, so `needs` resolves.
3. **DX-03, `--log-file $AFFECTED`.** Turbo parses it correctly (a dry run confirmed it). Reordering is cosmetic.
4. **TEST-01, untested SQL modules.** sessions, mfa, grants, actor and ensure-rls have integration tests in `sql-modules.integration.test.ts`. Only `realtime-tables` lacks a behavioural test (see Deferred).
5. **`tracedFetch` is missing** (part of DIR-3). It is public, tested and documented. The real gap was the batch span, which is fixed. Per-read spans inside a batch already existed.
6. **`checkReceipts` in the push block keeps stale tokens.** It prunes them.

## Deferred

1. **PERF-04, `tablesOf`.** Already cached; the remaining gain is small.
2. **PERF-05, sequential awaits.** Two loops could run in parallel, but that changes which error is reported first.
3. **A behavioural test for `realtime-tables`.**

## Left in place on purpose

- **29 `raise exception` sites** stay inline because `raise` cannot reproduce them byte for byte: `using` on its own line inside multi-line statements, raises without an errcode, and computed hints. They are in `jobs`, `credentials`, `streams`, `data-lifecycle`, `audit`, `workflow-sdk-world` and one site each in 13 other modules. The doc comment on `raise` in `src/sql/shared.ts` names these shapes instead of a comment at every site.
- **Inline grants:**
  - `rate-limit.ts` writes `on table`, which `revokeTable` does not emit.
  - `grants.ts` `tableGrants` revokes from `public` and `service_role` too and enables no RLS. It now has a comment saying why.
  - The dynamic `format('revoke all on %s ...')` revokes in `access.ts` and `workflow-sdk-world.ts`, plus that file's schema revoke, run inside plpgsql.
  - In `webhooks-out-sql.ts`, the clients grant also revokes from `authenticated`. The `list` and `count` grants in `audit-api.ts` revoke conditionally.
- **The function descriptor has no `name`.** `functionRoute(name, fn)` takes the name, which is the deployed function's directory and not something the handler knows.
- **`basePath` is prepended to `functionRoute` paths**, like every route. The docs say to document functions in an API without a `basePath`. A per-route opt-out would need a new `RouteSpec` key; add one only if an app asks.
- **The DEBT-3 bench run** exited 0 on its ratio checks; no before-and-after timing was captured, because the checks are ratios and the split moves no work.
