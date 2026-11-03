---
"better-supabase": minor
---

The `queue` block gets leases with a completed state and a bounded wait. The `queue` SQL module moves from version 9 to 10, so run `better-supabase upgrade`.

- New `createLeases(source)` in `better-supabase/blocks/queue` with `claim({ scope, key, timeoutMs, leaseSeconds })`, which answers `claimed`, `busy` (with `retryAfterMs`) or `completed`, and `withLease(options, fn)`, which extends the lease while `fn` runs, releases it when `fn` throws and marks it completed with `completeFor`.
- New SQL functions `claim_lease`, `extend_lease_claim`, `complete_lease` and `release_lease_claim` over a new `job_leases` table. The `idempotency` block's `acquire_lease` family and the `withLease` helper are unchanged.
- `startOnce` with a run registry now ends its dispatch claim when the workflow start throws, so the next caller starts the run at once instead of waiting for the 60 second lease.
