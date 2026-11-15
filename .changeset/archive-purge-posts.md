---
"better-supabase": minor
---

Breaking: posts can be archived and restored, and their hard delete is
`purge`, behind `permissions.purge` when you set it (ADR 1078). An archived post
leaves `list` unless `archived` is set and takes no votes, replies or edits.

| Before                  | After               |
| ----------------------- | ------------------- |
| `posts.delete(id)`      | `posts.purge(id)`   |
| `delete_post(id)` (SQL) | `purge_post(id)`    |
| event `post.deleted`    | event `post.purged` |

Run `better-supabase upgrade` and apply the migration, which adds
`archived_at` to posts. See the 0.66 to 0.67 guide.
