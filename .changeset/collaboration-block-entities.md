---
"better-supabase": minor
---

The comments, attachments, reactions, engagements, documents, calendar and reminders blocks declare their entities, so `blocks.<name>.entities` renames them like the other entity blocks: `{ comments: { entities: { comment: "note" } } }` turns the `comments` table into `notes`, `create_comment` into `create_note` and `comment.created` into `note.created`. Their table indexes and policies are now named after the table, so they follow a rename.

Installing comments, engagements, documents or calendar registers `comment`, `engagement`, `document` and `calendar_event` as subjects, so reactions, attachments, search, relations and the other subject blocks accept them with no `subjects` entry. Engagements and calendar events are indexed for search when the search module is installed. Comments, attachments, engagements and calendar export input schemas: `commentInputSchema`, `commentChangeSchema`, `attachmentInputSchema`, `engagementInputSchema`, `engagementChangeSchema` and `calendarEventInputSchema`.

To upgrade:

1. Remove `subjects.comment`, `subjects.engagement`, `subjects.document` and `subjects.calendar_event` from your config when the block that owns them is installed: a `subjects` entry with a block entity's name is an error. To keep your own entry instead, set `blocks.<name>.entities.<entity>.subject` to `false`.
2. Run `better-supabase sql sync`, then generate a migration. Reactions now checks a comment through the comment subject, which also requires `comments.read`, and refuses a reaction to any subject whose `deletedAt` is set. Its backfill setting is now `better_supabase.bs_reactions_backfill`.
3. If you set `tables` for one of these blocks, its policies get new names that follow the table; drop the old `<block>_read` style policies by hand after the migration, or leave them, since they are the same permissive select policies.
