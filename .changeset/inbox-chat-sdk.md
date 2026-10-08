---
"better-supabase": minor
---

The `inbox` SQL module and `better-supabase/blocks/inbox` add a shared support inbox per organization: contacts with channel identities, conversations with assignment, teams, status, snoozing and bot handoff, messages and internal notes, read receipts, deliveries, attachments in a private bucket and `purgeContact` for data subject requests. `useInbox`, `useConversation` and `useInboxWidget` from `better-supabase/blocks/inbox/react` keep a list, a thread and an in-app widget current over private Realtime topics.

`better-supabase/chat-sdk` runs Chat SDK bots on Supabase: `createSupabaseState` is a `StateAdapter` on the new `chat-sdk-state` SQL module, `inboxAdapter` answers in the in-app widget, and `webhook`, `inboundHandler`, `deliver`, `maintain` and `createChatInstallations` record Slack, WhatsApp, Messenger and SMS conversations in the inbox with platform tokens behind a `credential_ref`. `better-supabase/chat-sdk/react` re-exports the inbox hooks, and `testChatState` from `better-supabase/testing` checks any `StateAdapter`. `chat` is a new optional peer (`>=4.41 <5`).
