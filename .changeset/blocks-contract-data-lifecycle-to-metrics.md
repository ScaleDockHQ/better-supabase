---
"better-supabase": minor
---

More blocks meet the block contract. `createFlagAdmin` is now `createFlags`. `createJobs({ queues, sql })` replaces `createJobs(source, queues, options)`, taking its store as `backend`, `sql`, `client` or `transport`, and the jobs block is built by `createBlocks`. `createIdempotency({ sql })` and `createIncomingWebhooks({ sql })` take their connection as an option, and the entitlements block gets `createEntitlements` with `has` and `value`.

Deals, drive, employees, engagements, flags, forms, hiring, inventory and invoices take `options.extraColumns` on their main table and a Standard Schema as `fields`, which types and parses the columns on reads and validates them on writes. `create_form`, `update_form` and `save_location` take a `fields` argument. Data-lifecycle, entitlements, flags, idempotency, identities, imports, inbox, incoming webhooks, jobs, knowledge and memory accept `hooks`; inbox, knowledge and memory also take hooks per method group. Calls over a transport go through `blockCall`, so `mappers` apply to them.
