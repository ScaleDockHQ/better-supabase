---
"better-supabase": minor
---

Blocks run over the app's own tables everywhere, block calls return a `Result`, and Temporal values replace date strings. The upgrade guide is at [From 0.20 to 0.21](https://bettersupabase.com/docs/migration/0.20-to-0.21).

**Breaking:**

- `db.$api(fn, args, options)` returns an `AsyncResult` instead of throwing. Call `.orThrow()` for the old behavior, or read `.ok`. It takes `$rpc` options (the new `ApiOptions` type), and a `returns` schema validates and types the value. `db.$apiResult` from 0.19 is now a deprecated alias of `$api`.
- `DbBlockSource.call` is replaced by `api`, the name of the API schema; the core calls it through `$rpc`. `BlockSet.call` returns an `AsyncResult`, and `BlockSet.api` names the API schema.
- These fields are `Temporal.Instant` instead of strings: the argument of `reminders.markSent`, `DeliveryPayload.occurrenceAt`, `PlannedDelivery.occurrenceAt`, `Relation.createdAt`, `BulkRun.createdAt` and `finishedAt`, and `IncomingWebhook.createdAt` and `lastReceivedAt`. A bookings service's duration is a `Temporal.Duration`.
- An app table a block runs over must have the columns that block calls need. Calls that need a missing column fail with a `*_UNSUPPORTED` error, and a review reply without a reply column fails with `REVIEW_INVALID`.
- The default SQL of several blocks changed: identities, queue and collections upsert `on conflict` by columns, status columns are written explicitly, and the activities `externalRef` index exists only when the column is mapped. The line tables of quotes, invoices and deals get a `bsb_<lines>_position_key` unique index and upsert by position. Run `upgrade` and generate a migration.

**Added and fixed:**

- Temporal values are encoded at any depth in function arguments, `queryRaw` parameters and block fields. A `ZonedDateTime` is sent as its instant, and `Duration`, `PlainYearMonth` and `PlainMonthDay` have a wire form.
- Every block table can be the app's own table, except the `workflow-sdk` world. Line tables take optional columns and an enum `productType`. Idempotency, rate-limit, reserved-slugs, queue and `audit.registry` have `names.tables`, and their default SQL quotes identifiers.
- Tenant columns follow the config: state machine and numbering entities default to the `config.records` tenant, else `organization_id` (or its rename); `history.tenant` defaults to the machine's tenant column; the tasks pipeline, doctor's subject check and the legacy upgrades follow a renamed tenant; `gen` writes renamed tenant columns and the middleware reads them back as `tenant_id`.
- `orderMetrics`, `timeTrackingMetrics` and `driveSubject` take `table` and `tenant`; the workflow editor takes `tenantClaim`; the SCIM sync log maps through `blocks.sso.tables` and `columns`.
- Notifications deliver to adopted profiles whose locale column is an enum or a domain.
- The attachments trigger resets the scan state of client inserts into an app table. Adopted usage history is never partitioned and needs an increasing `bigint` id. Adopted ledger balances keep the app's grants.
- Render refuses two blocks that would create the same table, such as `blocks.idempotency.tables.leases` and `blocks.leases.tables.leases` both set to `better_supabase.leases`, and names both config keys.
