---
"better-supabase": minor
---

The webhooks block is a job source: `dispatchJob(input)` and `redeliverJob(deliveryId)` return `{ jobId: "webhook:<delivery id>" }`, and `webhooks.jobs` (the `webhook` kind of `createJobs`) reads the delivery back as the common `JobResult`. The new `get_webhook_delivery(delivery)` SQL function (webhooks module version 8) returns one delivery to a caller who may read its endpoint's organization; run `better-supabase upgrade` and apply the migration. `dispatch` and `redeliver` keep returning the delivery id.
