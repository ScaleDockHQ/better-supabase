---
"better-supabase": minor
---

Add presence on any record, record mentions with backlinks, and save for later.

- The subjects module authorizes Realtime presence on `presence:<type>:<id>` for anyone who can read the record. `subjectPresence` and `subjectPresenceValues(subject)` from `better-supabase/realtime` join it with `usePresence`, so a channel, a comment thread's record and a document share one helper. The `presence-avatars` UI recipe shows who else has a channel open.
- Messages and comments mention a record as `@[Name](subject:<type>/<id>)`. `messaging.recordMentions(subject)` lists the messages that mention a record, for its readers only, and `message.sent` carries the mentioned records as `recordMentions`. `mentionSegments`, `parseMentions`, `recordMention` and `userMention` from `better-supabase/blocks/messaging` parse and write the syntax, and the `message-list` recipe renders record mentions as chips.
- The collections block keeps a saved items list per member: `saveForLater(organizationId, subject, { note, remindAt })`, `saved`, `completeSaved` and `removeSaved`. `remindDue()` (service role) sends the `notification` you configure through the `notifier` port when a reminder is due and records `saved_item.reminded`. The block now consumes `notifier` as an optional port.

Run `better-supabase sql sync` and generate a migration to get the new tables, functions and policies.
