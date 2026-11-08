# 0460: Check storage, initplan and policy-index practices in doctor, prefer `db advisors`, pin the audience

- Status: accepted
- Date: 2026-11-08
- Amends: 0247

## Context

ADR 0247 added doctor BS365 to BS368 and a per-module practices baseline. The
declarative base layer plan lists more practices: a storage upsert needs insert,
select and update policies, policy calls to `auth.uid()` run inside a select,
and a policy column needs an index. It also asks doctor to read
`supabase db advisors` when the CLI has it, and token verification to pin the
audience next to the issuer.

## Decision

- Doctor BS383 (storage insert policy without select and update), BS384 (a bare
  `auth.uid()`, `auth.jwt()` or `auth.role()` in a policy) and BS385 (a policy
  column with no index that starts with it) read the app's schema files.
  `tests/sql/practices.test.ts` gains `policy-bare-auth-call` and
  `uncapped-page-limit`, both at zero. The generated storage buckets of
  `attachments` and `ai-files` are write-once (insert, select and delete), so
  the storage rule is a doctor code only and has no module baseline.
- `src/cli/doctor/cli-advisors.ts` runs `supabase db advisors --db-url ... -o json`
  for a loopback database when the CLI is 2.81.3 or later, so a password never
  reaches argv for a remote host. A missing or older CLI, a remote database or a
  failed run falls back to splinter at `SPLINTER_COMMIT` and `SPLINTER_SHA256`
  (invariant 13). Hosted projects keep the Management API.
- `resolveAuth` verifies `aud = authenticated` unless `auth.audience` is set.
  The issuer check stays as it is.
- `tests/auth/server-boundary.test.ts` rejects imports of
  `@supabase/server/adapters/*` and the legacy `allow`, `'always'` and `'public'`
  auth spellings.
- The docs page "Postgres and Supabase practices" lists each practice with its
  code.

## Alternatives considered

Adding update policies to the write-once buckets would let an object be
overwritten. Passing remote database URLs to the CLI puts the password on the
process list. Failing doctor when the CLI output changes would hide the
advisors, so a failure falls back to splinter.

## Consequences

Not done here: a doctor code for `verify_jwt = false` in a function that doesn't
verify the caller, `lock_timeout` in the generated hand migrations
(`cli/sql/migrations.ts` already sets it for `add --adopt`), batched seed
statements and a pgTAP `explain` test for initplans, which need the Supabase
stack. The `ANON_KEY` and `SERVICE_ROLE_KEY` fallbacks stay until the pinned CLI
prints the new names.
