# Plans

Improvement plans from the deep audit of 2026-10-11 (commit `1ea78cfa`; re-verified and executed on `9fcb32b6`). Each plan is fully self-contained: an executor with zero context from the audit session can run it. Every finding below was verified by reading the cited code directly; the audit ran without subagents at the user's request.

## Status

| Plan                                | Title                                                                                               | Status                                     |
| ----------------------------------- | --------------------------------------------------------------------------------------------------- | ------------------------------------------ |
| [001](001-codebase-improvements.md) | rpc JSON argument binding, and refusing database access for invalid credentials                     | DONE (uncommitted on `fix/audit-findings`) |
| [002](002-audit-triage.md)          | Triage of the 2026-10-12 audit: fixes, SQL helper cleanup, build splits, edge functions in the spec | DONE on `fix/audit-triage`                 |
| [003](003-presets-registry-create.md) | Composable blocks, presets, a shadcn-compatible registry, and Components, Blocks and Create on the website | TODO (after `feat/pipelines-foundation` merges) |

Update the Status column as you execute (`TODO` → `IN PROGRESS` → `DONE`/`BLOCKED`, with a note on what blocked it).

## Execution order

Plan 001's two findings are independent; either order works, and finding 1 (rpc JSON args) is the safer one to land first. Both are small. Run `pnpm verify` before pushing, and keep the two changesets in separate files so either finding can merge alone.

## Audit outcome

The audit covered the whole repository at deep effort: core execution (`core/`, `compile/`, `ir/`), auth (`resolve`, `refresh`, `session`, `ended`, `actor`, `hs256`), the server layer (`server.ts`, `clients.ts`, guards, refusals, replicas), the direct Postgres path (`pool.ts`, `executor.ts`), the blocks (`api-keys`, `webhooks` and its SSRF layer), the CLI, and the test and docs layout. Two findings survived vetting and became plan 001. The codebase is in strong shape: the strict invariants hold (Result errors, no module augmentation, lazy optional peers, parameterized SQL throughout the compiler and pool).

## Considered and rejected

Recorded so a future audit does not re-litigate them. Each entry names the claim and the evidence that settled it.

1. **`actingAs` lets callers mint `service_role` sessions** (the `...claims` spread after `role: "authenticated"` in `src/server/server.ts:678` to `684`). By design: the docs state "`actingAs` trusts its caller, so call it only after the signature check and the lookup" (`apps/docs/content/docs/guides/without-a-session.mdx:102`). Same trust model as `admin()`.
2. **Unbounded auth memo growth, or `clearVerifiedTokens` missing a reset.** Wrong on re-read: `secretIds` is bounded at 64 with eviction (`src/auth/resolve.ts:236` to `252`), and `clearVerifiedTokens()` clears the URL memo, the JWKS memo, `secretIds`, and the HS256 key cache (`src/auth/resolve.ts:287` to `292`).
3. **`statement_timeout` / `idle_in_transaction_session_timeout` as a missing feature.** Already implemented: per-role or single `statementTimeout`, plus `idleInTransactionTimeout`, on `createPostgres` (`src/postgres/pool.ts:148` to `177`).
4. **`signatureOf` returns `undefined` for zero-argument functions.** Withdrawn: the catalog query returns a row whenever the function exists, regardless of parameter count (`src/postgres/executor.ts:214`). The real gap in that function (JSON parameter types) is plan 001, finding 1.
5. **`begin()` leaks an open transaction into the pool when `set_config` fails.** Wrong: the catch rolls back and the `finally` releases the client (`src/postgres/pool.ts:209` to `214`).
6. **Honoring `https_proxy` in the webhook safe-fetch is an SSRF vector.** Proxy environment variables are the standard convention; by design.
7. **Session cookie chunking format (`base64-` prefix).** Documented and tested; settled.
8. **`refusal.ts` misses a case.** No gap found: it is the route guard's redirect and Problem Details layer, and it covers `unauthorized`, `aal2`, and authorizer refusals.
9. **Chunked writes coerce a null count to 0 (BUG-03).** Only inserts are chunked, and every insert plan returns a numeric count (plan 002).
10. **`needs: verify` cannot resolve in CI (DX-01).** `verify` is a job in the same `ci.yml` (plan 002).
11. **`--log-file $AFFECTED` misparses (DX-03).** A turbo dry run parses it correctly (plan 002).
12. **The sessions, mfa, grants, actor and ensure-rls modules are untested (TEST-01).** They have integration tests in `sql-modules.integration.test.ts`; only `realtime-tables` lacks one (plan 002).
13. **`tracedFetch` is missing from `otel`.** It is public, tested and documented; the missing batch span was fixed in plan 002.
14. **`checkReceipts` in the push block keeps stale tokens.** It prunes them (plan 002).

## Future direction (deferred, not planned)

Grounded opportunities in priority order. None is urgent; each needs its own plan if pursued. Per the audit brief, features were not bundled into plan 001.

1. DONE in plan 002 (`SessionOptions.statementTimeout`). **Per-query timeout override** on the direct Postgres path. `createPostgres` already has per-role `statementTimeout` (`src/postgres/pool.ts:148` to `153`); jobs that run one long query on a shared pool would benefit from a per-call override. Small.
2. **Auth observability hook.** `src/auth/resolve.ts` memoizes, refreshes, and re-verifies silently; a small metrics callback (cache hits, misses, refreshes) would make long-lived workers debuggable. Small to medium.
3. Superseded: the direct Postgres executor already batches the reads of one `db.$many` call, and plan 002 added a `BATCH` span for it. **Batching the direct Postgres executor.** `src/core/batch.ts` batches concurrent PostgREST reads into one round trip; `src/postgres/executor.ts` runs queries one by one. Batching concurrent reads into a single transaction would help job workloads. Medium.
4. DONE in plan 002 (OUT and TABLE arguments are dropped). **OUT-parameter filtering in rpc calls.** PostgREST drops OUT parameters from generated calls; `callFunction` binds whatever the caller passes (`src/postgres/executor.ts:262` to `268`). Small; only matters for OUT-parameter functions.
5. **`tablesOf` (PERF-04).** Already cached; the remaining gain is small (plan 002).
6. **Sequential awaits (PERF-05).** Two loops could run in parallel, but that changes which error is reported first (plan 002).
7. **A behavioural test for `realtime-tables`** in `sql-modules.integration.test.ts` (plan 002).

## Scope notes

- The plan touches only `packages/better-supabase`. The apps, docs, and examples were audited by reading but hold no vetted findings.
- `src/server/server.ts` was verified read-only for plan 001: the request paths into `restAt`/`supabaseFor` are the lazy `get db()` getters (lines 313, 362, 435), so finding 2's throw fires only when a handler touches `db`.
- The docs cross-check that motivated finding 2: `apps/docs/content/docs/auth/index.mdx:24` documents `invalid` as "answer 401", and `apps/docs/content/docs/extending/conformance.mdx:37` requires resolvers to return "invalid (never anon)" for bad credentials.

## Reconciliation

To process outcomes after execution, reopen this README, flip the status of executed plans, and re-verify the Done criteria of any plan marked `DONE` against a fresh checkout. If a plan is `BLOCKED`, move its finding back here under "Considered and rejected" with the blocking evidence, so the next audit does not repeat it.
