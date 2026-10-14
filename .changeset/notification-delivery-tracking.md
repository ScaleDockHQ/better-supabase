---
"better-supabase": minor
---

The notifications module tracks what an email provider reports after a send. `notification_delivery_events` stores each `delivered`, `opened`, `clicked`, `bounced`, `complained` or `delayed` event once per provider event id, and deliveries gain `provider_status`, `provider_status_at` and `template_key`. `notifications.recordDeliveryEvent(input)` calls the service-only `record_delivery_event`, which moves the status forward, suppresses the address on a hard bounce or a complaint, and emits `notification.<kind>` with the notification's subject. `notifications.subjectDeliveries({ subject })` lists the deliveries of every notification about one record. A `templateKey` returned from the email channel's `compose` is stored on the delivery.

`resendWebhook` now records every Resend delivery status before it writes suppressions, and `resendDeliveryEvent(event, id)` maps one event without the handler. `notification.delivered` and `notification.failed` now carry `subjectType`, `subjectId`, `organizationId` and `deliveryId`, and the five new events are subject events.

`complete_notification_delivery` takes a seventh argument, `template_key`, and the six-argument signature is dropped. Run `better-supabase sql sync` to install module version 6; `resendWebhook` answers 500 against a database without `record_delivery_event`. An adopted module tracks delivery events only when `tables.deliveryEvents` names your table.
