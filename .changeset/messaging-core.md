---
"better-supabase": minor
---

Add the `messaging` block: conversations, members, threaded messages, edits, pins, mentions, scheduled messages, read markers and typing, which channels, comments and the inbox build on (ADR 0062). See [Messaging](https://bettersupabase.com/docs/blocks/messaging).

The inbox renames the names that now belong to the core. Run `better-supabase sql upgrade` (the inbox module moves to version 3) and update your calls:

| Before                                        | After                                                           |
| --------------------------------------------- | --------------------------------------------------------------- |
| the `conversations` table                     | `inbox_conversations`                                           |
| `send_message`, `edit_message`, `get_message` | `send_inbox_message`, `edit_inbox_message`, `get_inbox_message` |
| `list_messages`, `list_conversations`         | `list_inbox_messages`, `list_inbox_conversations`               |
| `set_typing`                                  | `set_inbox_typing`                                              |

`createInbox` and the Chat SDK inbox adapter call the new names, so apps that go through them need no change beyond the upgrade.

- `createMessaging` in `better-supabase/blocks/messaging` opens channels, direct and group messages and record conversations, sends, edits and threads messages, lists conversations with unread and mention counts, and moves read markers.
- Messages and conversations are entities, so reactions, attachments, share links and search accept them, and `blocks.messaging.entities` renames them.
- Mentions notify readers of the conversation, direct messages notify the other people in them, and thread replies notify the thread's followers.
- The `messages.read`, `messages.send` and `messages.moderate` permissions join the default roles.
- `ctx.enqueue` in module code takes a `delay`.
