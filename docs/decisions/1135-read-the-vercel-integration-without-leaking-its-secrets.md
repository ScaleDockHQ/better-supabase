# 1135: Read the Vercel integration's variables without leaking its secrets

- Status: accepted
- Date: 2026-11-21

## Context

The Supabase Marketplace integration on Vercel syncs `POSTGRES_URL` (pooled)
and `POSTGRES_URL_NON_POOLING` (direct) next to the Supabase keys. The runtime
pool and `parseEnv` already read them, but the CLI and the Workflow World did
not, so `gen`, `db` and `createWorld()` needed a copy under another name. Two
choices were open: which of the two strings wins, and how a callback to a
protected deployment gets the `x-vercel-protection-bypass` secret.

## Decision

The CLI reads `POSTGRES_URL_NON_POOLING` before `POSTGRES_URL`, after
`SUPABASE_DB_URL` and `DATABASE_URL`, because introspection and `db` need a
session that a transaction pooler does not give. The World and the pool keep
the pooled string first, which is what a long-running server wants, and both
orders are in `docs/vercel/deploy`.

`better-supabase/vercel` returns the bypass header only when the target host is
one of the deployment's own (`VERCEL_URL`, `VERCEL_BRANCH_URL`,
`VERCEL_PROJECT_PRODUCTION_URL`) or is listed in `allowHosts`. The World applies
it to its flow route that way, and an explicit `deliveryHeaders` entry wins.
`doctor --vercel` compares variable names from the files `vercel pull` writes,
because Vercel returns no value for a sensitive variable.

## Alternatives considered

- The same order everywhere. The pooled string breaks session features in the
  CLI, and the direct string costs a connection per server instance.
- Always attach the secret to a configured callback URL. A misconfigured URL
  would send the project's bypass secret to a third party.
- `doctor --vercel` over `vercel env ls --format json`. Its output shape is not
  documented as stable, and the files are what `vercel pull` writes today.

## Consequences

A project on the integration needs no renamed variables. The secret never
leaves the deployment's own hosts without a listed host. Revisit the CLI order
if Supabase moves the direct string behind IPv6 only, and the doctor input if
Vercel documents a stable JSON listing.
