---
"better-supabase": minor
---

`createNotifications` takes `email: { transport, from, compose?, unsubscribe? }`, an email channel over a `DeliveryTransport` (`apiVersion: 1`) that sends with the delivery id as the idempotency key, sets `Auto-Submitted: auto-generated` on all mail and `List-Unsubscribe` with one-click `List-Unsubscribe-Post` on notification mail only. `better-supabase/blocks/notifications` exports `resendTransport` (fetch-based, `Idempotency-Key` header), `resendWebhook` (verifies the Svix signature and records bounces and complaints), `mailHeaders` and `resendSuppressions`, and `better-supabase/testing` gets `testDeliveryTransport`.

The notifications module (version 5) adds `notification_suppressions` with RLS and `suppress_notification_address`, `unsuppress_notification_address` and `list_notification_suppressions`; the block gets `suppress`, `unsuppress` and `suppressions`, and `deliver` skips a suppressed address. `createNotifications({ audience })` checks recipients before sending and falls back to `server.authorization.delivery.audience`. `defineTopic` takes `permission` (an instance permission from a topic segment, checked with the provider's `permitted` template or the access contract) and `subscribers`, and topics get `fanOut`.

Breaking: run `better-supabase sql sync` and create a migration for the module upgrade; an adopted module honours suppressions only when `tables.suppressions` is mapped. `deliver()` counts suppressed and audience-denied deliveries in `skipped`. A hand-written `Topic` object needs `fanOut`.
