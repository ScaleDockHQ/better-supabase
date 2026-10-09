---
"better-supabase": minor
---

The `inbox` SQL module and `better-supabase/blocks/inbox` add a shared support inbox per organization, and `better-supabase/chat-sdk` runs Chat SDK bots on it (`chat` `>=4.41 <5` is an optional peer).

- The inbox stores contacts, conversations with assignment, teams, snoozing and bot handoff, messages and notes, read receipts, deliveries and attachments, with `purgeContact` for data subject requests. `useInbox`, `useConversation` and `useInboxWidget` in `/blocks/inbox/react` stay current over private Realtime topics.
- `createSupabaseState` is a `StateAdapter` on the `chat-sdk-state` module, `inboxAdapter` answers in the in-app widget, and `webhook`, `inboundHandler`, `deliver`, `maintain` and `createChatInstallations` record Slack, WhatsApp, Messenger and SMS conversations. `testChatState` checks any `StateAdapter`.
