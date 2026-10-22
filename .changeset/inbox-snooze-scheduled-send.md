---
"better-supabase": minor
---

The inbox block schedules staff replies and wakes snoozed conversations on time.

- `inbox.messages.schedule(conversationId, input, at)` saves a reply for later in the new `scheduled_inbox_messages` table. Only its author sees it (`messages.scheduled`), moves it (`reschedule`) or deletes it (`cancelScheduled`). `inbox.publishDue()` (service only) sends the due replies through the normal reply path as their authors, and drops a reply whose author lost `inbox.reply`.
- Snoozing needs a time in the future: `set_conversation_status` with a past `snoozed_until` now fails with `INBOX_SNOOZE_UNTIL` (`22023`).
- `wakeSnoozed()` logs `unsnoozed` in the conversation's events, emits the new `inbox_conversation.unsnoozed` event and notifies the assignee, or the inbox's members while nobody is assigned (`inbox.snooze_ended`).
- With the jobs block, snoozing and scheduling queue a delayed job on `inbox_schedule` (the new `scheduleQueue` option) for the right time, so a handler that calls `wakeSnoozed()` and `publishDue()` runs them without a cron.
- The chat-sdk `maintain()` also sends the due replies and returns their count as `published`.

Run `better-supabase sql sync` and generate a migration for the new table and functions.
