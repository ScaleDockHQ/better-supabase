---
"better-supabase": minor
---

`devices.checkReceipts()` emits the `notification.delivered` and `notification.bounced` block events for the receipts it records, with the same data `recordDeliveryEvent` emits (`provider: "expo"`, `providerEventId: "expo-receipt:<ticket id>"`). Before, a push receipt reached the delivery history but no `betterSupabase.on` handler. `createPush` takes `events`, `actorId` and `context` for it. The push module moves to version 3: `complete_push_receipts` returns `{ updated, events }` instead of the ticket count, so run `better-supabase upgrade` and generate a migration.
