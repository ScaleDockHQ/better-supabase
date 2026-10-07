---
"better-supabase": minor
---

Reliability fixes across the blocks and their SQL modules. Run `better-supabase sql upgrade` after updating: the outbox (version 3), webhook inbox (version 5) and webhooks-in (version 2) modules ship upgrade steps.

- Outbox: a consumer whose handler throws backs off (`maxBackoff`, 10 minutes by default) and then claims one event at a time. An event that fails `maxAttempts` times (10 by default) moves to the consumer's dead letters, which `outbox.deadLetters(consumer)` returns, and the cursor passes it. `purge` takes `{ ignoreIdle }` to stop waiting for consumers that stopped claiming, and deletes old dead letters.
- Webhook inbox: `complete_webhook`, `fail_webhook` and `checkpoint_webhook` take the claimed attempt, so a worker whose lease was taken over can no longer finish the message. `process` renews each message's lease while its handler runs (`extend_webhook`), and `createInbox` takes `maxBodyBytes` (1 MiB by default) and answers `413` past it.
- Outgoing webhooks: a URL check that fails to resolve the host retries the delivery instead of marking it dead.
- Incoming webhooks: `hmac-sha256` endpoints dedupe deliveries on their signature, since the id header isn't signed, so a replayed body is stored once. Bodies are read up to the endpoint's limit instead of in full. Signing secrets are kept in Vault; the upgrade step copies existing secrets there, and `secretStorage: "column"` keeps the previous storage.
- Usage: `unreported_usage` counts a day from an earlier billing period within that period, so a late overage report sends the right amount. `consume_quota` locks per tenant and meter, so calls on either side of UTC midnight can't both take the last unit of a quota.
- Billing: `ensureCustomer` creates the Stripe customer with the idempotency key `customer:<organizationId>`, so two concurrent first calls create one customer.
- Audit: `purgeAuditLog` with `setAuditRetention` reads every tenant's retention in one query.
- Indexes for the purges of finished outgoing deliveries and processed or dead inbox messages, and for the user columns of `organization_domains`, `scim_users`, `data_exports`, `organization_deletions` and `incoming_webhooks`.
