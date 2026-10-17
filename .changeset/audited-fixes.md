---
"better-supabase": minor
---

Fixes from an audit of the blocks, the jobs worker, the commerce adapters and the CLI.

Breaking: `fromStripeAmount` returns a `Result<Money>`. It refuses an amount that isn't a safe integer, or an ISK or UGX amount with a fraction of the minor unit, with `invalid_input` and the hint `STRIPE_AMOUNT_PRECISION`, where it used to truncate. The Stripe payments and tax adapters return that error instead of a wrong amount.

The notifications and settings blocks split their own-row `for all` policies into read, insert, update and delete policies, so `actor_may_write()` guards writes only and a read-only support session can still read. Run `better-supabase sql sync` and generate a migration.

- The data-lifecycle purge checks the legal hold and the due date before it deletes storage objects or calls a webhook.
- A jobs worker aborts a job's signal when its lease can't be extended, and reports `JOB_LEASE_LOST` through `onError` instead of completing a job another worker may hold. A failed `complete` is reported too.
- The idempotency middleware answers `409` with `IDEMPOTENCY_KEY_LOST` when the lock expired before the response was saved, and the request fingerprint includes the query string.
- The webhook inbox passes its handler an `AbortSignal` that aborts when the lease can't be renewed, and then leaves the message to the next worker.
- The outbox treats a handler that returns a failed `Result` as a failure, so the event is retried.
- `deleteAccount` succeeds on a retry for a user that Auth already deleted, and still removes the listed storage objects.
- Invoice deposits are computed in `numeric`, so line totals round half away from zero past 2^53.
- The search block adds a partial index for rows waiting for an embedding.
- `env --out`, `env.output` and `env --from` refuse a path outside the project root.
- A `42501` error says "permission denied" to the client, and keeps the object name and PostgREST's grant recipe in `details`.
- `queueBackend({ client, schema })` calls the wrappers `blocks.jobs.api` writes into that schema, for the full feature set over the Data API. `client` alone still uses the `pgmq_public` RPCs.
- `supabaseCollection` from `better-supabase/tanstack-db/supabase` works with `casing: 'camel'` and with tables outside `public`: it renames filters, bodies, rows and Realtime payloads, and runs requests and Realtime listeners in the table's schema.
- A subject's `deletedAt` column becomes the table's `softDelete` flag in `gen` (it wins over `plugins.softDelete.column`), and declared metrics skip those rows unless the metric sets `includeDeleted: true`.
