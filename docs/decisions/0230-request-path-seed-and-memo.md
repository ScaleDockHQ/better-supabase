# 0230: Seed the authorizer from the session and memoize the audit and updated-at helpers

- Status: accepted
- Date: 2026-11-03

## Context

A page render made several sequential round trips that did the same work again: each
`can()` call read the permission version, each scope verified the token, and a bulk
write fired one audit trigger run per row. The request path benchmarks in
`tests/bench` showed these as the largest share of the latency of a customer page.

## Decision

The authorizer receives its seed (the claims, the version and the cache slot) from the
session handle, so a nested scope reuses one verification and one version read. The
permission version sits in the version cache slot of ADR 0096 and 0114.

The SQL helpers that run once per statement (`auth.jwt()` and request headers) are
read into a variable at the start of the function. The audit and updated-at modules
keep the shared helpers in `MEMO_FUNCTIONS`, in the `updated-at` module.

Audit can record by statement: three statement triggers use transition tables and write
one insert per statement. The mode needs a primary key and rejects deferred, tenant
path and tenant function configurations. `doctor --explain-write` plans one insert and
one update in a rolled-back transaction and reports the trigger times.

## Alternatives considered

- Cache the version in process memory without the slot. It would not survive a version
  change on another instance, and ADR 0096 already defines the slot.
- Make statement mode the default. A key change is recorded as a delete plus an insert,
  which changes the log for existing apps.
- Memoize in each module. The helpers would drift apart.

## Consequences

A customer page costs one call per read set, and a bulk write costs one audit insert.
Revisit the memo list if Postgres starts to inline `auth.jwt()` reads on its own, and
revisit statement mode if tables without a primary key need it.
