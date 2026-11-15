---
"better-supabase": minor
---

Pages the AI and messaging blocks by the block list contract (ADR 1077).
`agents`, `ai-chat` (chats and projects), `ai-files`, `ai-keys` (keys and
batches), `ai-schedules`, `knowledge` (documents and collections), `ai-evals`
(datasets and runs), `ai-guardrails` (policies and decisions), `inbox`,
`channels`, `messaging`, `posts` (posts and boards) and `memory` (archival
facts) gain `page`, `facets` and `count` with `q`, sorts, array filters and a
keyset cursor, and a read of one row that returns a `not_found` error for an
unknown id (`getConversation`, `getChannel`, `getPost`, `getDataset`, `getRun`,
`getPolicy`, `getBatch`, `get`). The SQL adds the `page_*` and `get_*`
functions for them, and the generated schema files need
`better-supabase upgrade`. Blocks with a tenantless scope (ai-evals,
ai-guardrails, memory) take no `organizationId` for their system rows.
`comments`, `timeline` and `share-links` stay as they are: they read one
subject, and their docs pages say so. The array methods keep working and are
deprecated.

| Old                                            | New                                     |
| ---------------------------------------------- | --------------------------------------- |
| `agents.list`                                  | `agents.page`                           |
| `ai-chat` `chats.list`, `projects.list`        | `chats.page`, `projects.page`           |
| `aiFiles.files.list`                           | `files.page`                            |
| `aiKeys.keys.list`, `batches.list`             | `keys.page`, `batches.page`             |
| `aiSchedules.list`                             | `aiSchedules.page`                      |
| `knowledge.documents.list`, `collections.list` | `documents.page`, `collections.page`    |
| `evals.datasets.list`, `runs.list`             | `datasets.page`, `runs.page`            |
| `guardrails.policies.list`, `decisions.list`   | `policies.page`, `decisions.page`       |
| `inbox.conversations.list`, `get`              | `conversations.page`, `getConversation` |
| `channels.list`, `get`                         | `channels.page`, `getChannel`           |
| `messaging.conversations`                      | `conversationPage`                      |
| `posts.list`, `boards`, `get`                  | `posts.page`, `boardPage`, `getPost`    |
| `memory.archival.list`                         | `memory.archival.page`                  |
