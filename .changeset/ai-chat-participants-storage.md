---
"better-supabase": minor
---

The `ai-chat` block runs without a tenant, shares chats with participants, can store a linear list of native AI SDK parts keyed by uuid, and takes extra columns on every table (ADR 0122). `better-supabase upgrade` moves the module to version 5.

- `blocks["ai-chat"].options.tenant: false` lets chats and projects live outside a tenant: `chats.create(null, input)` and `projects.create(null, input)`. Such a chat stays private to its owner and its participants, and the AI SDK adapter skips the quota and the `org:` gateway tag for it.
- `participants.add(chatId, userId, { role })`, `remove` and `list` share a chat with viewers and editors, stored in the new `ai_chat_participants` table. In a tenant chat a participant must be able to read the tenant's chats and counts only while a member. `chats.list` returns the chats the caller owns or takes part in, and user messages record their writer (`authorId`).
- `blocks["ai-chat"].options.messages: { key: "uuid", tree: false, parts: "native" }` keys messages by uuid, keeps one list per chat instead of a tree, and stores the SDK's own parts. Choose it before installing; a uuid key needs uuid message ids (`AI_MESSAGE_INVALID` otherwise), and `switchBranch` on a linear chat fails with `AI_CHAT_LINEAR`.
- Every ai-chat table takes extra columns: `projectExtraColumns`, `participantExtraColumns`, `messageExtraColumns`, `moderationExtraColumns` and one key per other table. `appendUser`, `saveAssistant`, `projects.create`, `projects.update`, `participants.add` and `moderation.record` take `fields` for them.

Breaking changes:

| 0.34                                                              | 0.35                                                |
| ----------------------------------------------------------------- | --------------------------------------------------- |
| `organizationId: string` on chats, projects and moderation events | `organizationId: string \| undefined`               |
| `AssistantContext.organizationId: string`                         | `AssistantContext.organizationId: string \| null`   |
| `chats.create(organizationId: string, ...)`                       | `chats.create(organizationId: string \| null, ...)` |
| `projects.list(organizationId: string)`                           | `projects.list(organizationId: string \| null)`     |
| private chats: readable by the owner only                         | readable by the owner and the chat's participants   |
