# 1044: Archive, restore and purge for funding claims (lane Y2)

- Status: accepted
- Date: 2026-11-15
- Amends: 1041

## Context

A funding claim is built from approved deliveries and sent to a funder. Only a
draft could be deleted, and a claim the funder answered stayed in the list for
good.

## Decision

`funding` gets `archiveClaim`, `restoreClaim` and `purgeClaim`.

- An optional `archived_at` column marks an archived claim.
- `archive` accepts only a claim the funder answered (`accepted`, `rejected`,
  `partially_accepted`); a draft is purged and a sent claim waits for its
  answer. Archiving keeps the lines and deliveries, so billing history holds.
- `restore` clears the mark. Both are idempotent and record
  `funding_claim.archived` and `funding_claim.restored` once.
- `purge` replaces `deleteClaim` and `delete_funding_claim`. It is for drafts,
  needs `permissions.purge` (falling back to the claim key), releases the
  deliveries and records `funding_claim.purged`.
- Read paths: `list_funding_claims(include_archived)` hides archived claims by
  default, and `invoice_funding_claim` refuses an archived claim until it is
  restored.

## Consequences

Breaking: `deleteClaim`, `delete_funding_claim`, the `funding_claim.deleted`
event, and `list_funding_claims` gains an argument, so the migration recreates it.
