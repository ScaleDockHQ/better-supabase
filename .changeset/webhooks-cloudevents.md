---
"better-supabase": minor
---

Breaking: outgoing webhooks send a CloudEvents 1.0 event in structured mode (`content-type: application/cloudevents+json`) instead of `{ type, timestamp, data }`, and `transform` now returns the event's `data`. The event's `id` is the delivery id; `source`, `subject`, `time`, `dataschema` and `traceparent` come from the new `source`, `appUrl`, `typePrefix`, `dataschema` and `traceparent` options and from `publish({ subject })`. An endpoint with `batch = true` gets a CloudEvents batch (`application/cloudevents-batch+json`) per delivery run.

Breaking: `publish_webhook_event` is now `(event_type, payload, tenant, event_id, subject, read_permission)`, and the old four-argument function is dropped. It queues an event only for endpoints whose owner may read it: a user owner needs `read_permission` (else the module's view permission) through the authorization provider or the access contract, and a service endpoint (`created_by` null) needs it in its new `permissions` column. User endpoints get nothing when neither the provider nor the access contract is installed. `createWebhooks` and `createOutbox` take `subscribers` (a `SubscriberPolicy`) and fall back to `authorization.delivery.subscribers`; deliveries it leaves out are canceled, and outbox events it leaves out are counted as `refused`. Adopted webhook tables keep working: the new `permissions`, `batch` and `subject` columns are used only when mapped. Rerun `better-supabase sql sync` to install version 3 of the `webhooks-out` module.

Breaking: Problem Details for `invalid_request`, `unauthorized`, `forbidden`, `not_found`, `conflict`, `rate_limited` and `unexpected` at their default status use `"type": "about:blank"` and the HTTP status phrase as the title. Other kinds keep `https://bettersupabase.com/problems/<kind>`. `better-supabase codemod 0.9` does not rewrite these strings, so update clients that compare on `type` or `title`.

| Old title           | New title               |
| ------------------- | ----------------------- |
| `Invalid request`   | `Bad Request`           |
| `Not found`         | `Not Found`             |
| `Too many requests` | `Too Many Requests`     |
| `Unexpected error`  | `Internal Server Error` |

`verifyWebhook` and `verifyStripeWebhook` take a `seen(id, until)` hook and refuse a replayed message id with a `conflict` error (`WEBHOOK_REPLAYED`); a throwing hook gives `WEBHOOK_DEDUPE_FAILED`. A malformed `whsec_` secret now fails with `WEBHOOK_INVALID_SECRET` instead of throwing.
