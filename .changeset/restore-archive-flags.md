---
"better-supabase": minor
---

`deals`, `tasks`, `messaging`, `channels`, `collections` and `accounting` get a
`restore` next to their `archive`, and a restore records an event. `archive`
with `archived: false` still works and records the same event. Each method
needs the permission its `archive` needs.

| Block         | New method                        | New event               |
| ------------- | --------------------------------- | ----------------------- |
| `deals`       | `restore(dealId)`                 | `deal.restored`         |
| `tasks`       | `restore(taskId)`, `restore(ids)` | `task.restored`         |
| `messaging`   | `restore(conversationId)`         | `conversation.restored` |
| `channels`    | `restore(channelId)`              | `conversation.restored` |
| `collections` | `restore(id)`                     | `collection.restored`   |
| `accounting`  | `restoreAccount(accountId)`       | none                    |

Run `better-supabase upgrade` and apply the migration, which replaces
`archive_deal`, `archive_task`, `archive_tasks`, `archive_conversation` and
`archive_collection`.
