---
"better-supabase": major
---

Move the inbox onto the messaging core. Inbox conversations are core conversations of kind `inbox`, and messages and internal notes are core messages, so the inbox shares read markers, typing, mentions, files and reactions with channels and comments. See [Inbox](https://bettersupabase.com/docs/blocks/inbox) and the upgrade steps in [From 0.13 to 0.14](https://bettersupabase.com/docs/migration/0.13-to-0.14#the-inbox-on-the-messaging-core).

- The inbox block now requires `messaging` and `attachments`, and reactions on inbox messages need the `reactions` block.
- Notes are messages with `kind: "note"` that only staff read. Read markers live in `conversation_members.last_read_at`, and typing goes through messaging's `set_typing`.
- Files are scanned attachment rows. Upload with `messages.createUpload` and `confirmUpload`; channel files wait in `files.pending()` until the chat-sdk `importFiles` fetches and confirms them.
- `useConversation`, `useInboxWidget` and their controllers take `get(messageId)` and fetch only the message a Realtime ping names.
- The inbox module goes to version 4. `better-supabase sql upgrade` moves conversations, messages, notes, participants, read markers, files and reactions with their ids, then drops the old tables and functions.

| Before                                                                 | After                                                                      |
| ---------------------------------------------------------------------- | -------------------------------------------------------------------------- |
| `inbox_messages`, `conversation_participants`, `conversation_reads`    | `messages` with `inbox_message_details`, `conversation_members`            |
| `set_inbox_typing`                                                     | `set_typing(conversation, typing, actor)`                                  |
| reactions on `{ type: "inbox_message", id }`                           | reactions on `{ type: "message", id }`, through `react_to_inbox_message`   |
| `messages.react` and `InboxMessage.reactions` as `{ [emoji]: actors }` | arrays of `{ emoji, count, reacted, actors }`                              |
| `InboxMessage.mentions`                                                | `mentionIds`                                                               |
| `authorId`, `editedAt`, `deletedAt` as `null`                          | `undefined`; a contact's id is `conversation.contactId`                    |
| `MessageAttachment`, paths in `MessageInput.attachments`               | upload ids in `attachments`, channel files as `InboxFileSource` in `files` |
| `PurgedContact.attachments` as paths                                   | `{ bucket, path }` records                                                 |
| the topic `inbox:<conversationId>`                                     | `messages:<conversationId>`                                                |
