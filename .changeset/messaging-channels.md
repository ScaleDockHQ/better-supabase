---
"better-supabase": minor
---

Add the `channels` block: public and private team channels on the messaging core, with topics, purposes, membership, archiving and an optional linked record. See [Channels](https://bettersupabase.com/docs/blocks/channels).

- `createChannels` in `better-supabase/blocks/channels` creates, updates, archives, joins, leaves, invites, lists, browses and finds channels, and lists the channels linked to a record.
- Channels are an entity, so search, share links and reactions accept them, and `blocks.channels.entities` renames them.
- `useMessages` and `useConversations` in `better-supabase/blocks/messaging/react` (and the Vue, Svelte and Solid entries) keep a conversation's messages, a thread, who is typing and the conversation list live over Realtime. `createMessagesController` and `createConversationsController` run them without a framework.
- The `chat` preset installs `saas` with messaging, channels, reactions and attachments.
- The `channels.create` and `channels.manage` permissions join the default roles.
- The recipes `channel-sidebar`, `message-list`, `message-composer` and `thread-panel` build a chat screen.
