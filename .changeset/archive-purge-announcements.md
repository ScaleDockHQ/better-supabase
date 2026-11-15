---
"better-supabase": minor
---

Breaking: announcements can be archived and restored, and their hard delete is
`purge`, behind `permissions.purge` (ADR 1042). Archived announcements leave
`listActive` and `list`; `list({ includeArchived: true })` adds them.

| Before                          | After                                  |
| ------------------------------- | -------------------------------------- |
| `announcements.remove(id)`      | `announcements.purge(id)`              |
| `delete_announcement(id)` (SQL) | `purge_announcement(id)`               |
| event `announcement.deleted`    | event `announcement.purged`            |
| `list_announcements()` (SQL)    | `list_announcements(include_archived)` |

Run `better-supabase upgrade` and apply the migration, which adds
`archived_at`. See the 0.66 to 0.67 guide.
