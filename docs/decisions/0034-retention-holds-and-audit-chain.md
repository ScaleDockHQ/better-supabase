# 0034: Retention policies, legal holds and a hash-chained audit log in Postgres

- Status: accepted
- Date: 2026-10-16

## Context

Each module's purge took its own `older_than`, so a tenant's contract or
plan couldn't keep audit entries for seven years while free tenants keep
one, and nothing stopped a purge during litigation. Auditors also ask for
evidence that the audit log wasn't rewritten, and a log that grows for
years makes row-by-row deletes slow.

## Decision

`data-lifecycle` owns `retention_policies` (per kind, for every tenant, a
plan or one tenant) and `legal_holds` (a tenant or all, a kind or all).
Modules read them through the module context: `ctx.retention`, `ctx.held`,
`ctx.expired` and `ctx.cutoff`. These render calls to
`retention_for`, `is_held` and `retention_cutoff` when data-lifecycle is
installed, and the plain `older_than` (or `false` for a hold) when it
isn't, so no module requires data-lifecycle. Holds also block
`purge_organization`.

`audit` gains two options. `chain` adds `chain_seq`, `prev_hash` and
`row_hash` columns filled by a before-insert trigger under a per-tenant
advisory lock. The hash is SHA-256 over the previous hash and the row's
JSON, with the timezone fixed to UTC. `verify_audit_chain` walks a tenant's
range, and checkpoints store a JWS over each head that the app signs in
TypeScript with any `signJwt` signer, such as the signing-keys block's
(ADR 0033). `partitioned` creates a new managed log partitioned by month,
with a shared `ensure_partitions`/`maintain_partitions` helper and a
partition drop in `purge_audit_log` when no hold or hook applies.

## Alternatives considered

- Retention in TypeScript callbacks only (`setAuditRetention`): it stays for
  per-tenant columns, but it doesn't reach the other modules' purges or
  holds.
- An external append-only store (a ledger database or object lock): it
  adds a provider, and the chain plus signed checkpoints published as a
  JWK Set gives the same check with Postgres alone.
- Converting an existing log to partitions in a migration: that rewrites
  the table under a lock. Doctor (BS335) reports it, and the app moves the
  rows.

## Consequences

Each chained insert takes a per-tenant advisory lock, so one tenant's audit
writes are serialized. Entries written before `chain` was on stay outside
the chain. A partitioned log has a composite primary key and a non-unique
idempotency index, because a unique index on a partitioned table must
include the partition key. Revisit when Postgres supports global indexes.
