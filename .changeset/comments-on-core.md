---
"better-supabase": major
---

Move comments onto the messaging core, and the activity feed into its own `activity` block. A record's comments are now its messaging conversation, so comments get resolve, pins, edit history, anchors, attachments and read markers from messaging, and `assign` turns a comment into a work item. See [Comments](https://bettersupabase.com/docs/blocks/comments), [Activity](https://bettersupabase.com/docs/blocks/activity) and the upgrade steps in [From 0.13 to 0.14](https://bettersupabase.com/docs/migration/0.13-to-0.14#comments-on-the-messaging-core).

- The comments block now requires `tenant`, `access`, `subjects` and `messaging`, and runs in the `tenant` scope only. Register each record type you comment on in `config.subjects`.
- The comments module goes to version 8. `better-supabase sql upgrade` moves each record's comments into one conversation, keeps every comment's id, author, body, document, mentions, thread and timestamps, moves reactions and attachments on a comment to the message, and drops the `comments` table and its functions.
- Followers of a record get the `comment.posted` notification, and mentioned users get messaging's `message.mentioned`.
- `better-supabase/blocks/activity` exports `createActivity`, `activitySink`, `activityListQuery` and `activityBlock`. The crm, projects, helpdesk and docs presets include it.

| Before                                                                           | After                                                                                                |
| -------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `comments.read`, `comments.create`, `comments.moderate`                          | `messages.read`, `messages.send`, `messages.moderate`                                                |
| `comments.activity`, `blocks.comments.permissions.activity`                      | `activity.read`, `blocks.activity.permissions.read`                                                  |
| `comment.created`, `comment.deleted`                                             | `message.sent`, `message.deleted`, with `conversationKind`, `recordType` and `recordId` on a comment |
| `comment.mentioned`                                                              | the `message.mentioned` notification                                                                 |
| `commentsEvents`, `CommentsEvents`                                               | `messagingEvents`, `MessagingEvents` from `better-supabase/blocks/messaging`                         |
| `comments.history(organizationId, subject?, options?)`, `ActivityHistoryOptions` | `createActivity({ transport, tenant }).list(subject?, options?)`, `ActivityListOptions`              |
| `activitySink`, `activityListQuery` from `better-supabase/blocks/comments`       | the same names from `better-supabase/blocks/activity`                                                |
| `blocks.comments.options.subjects`                                               | `config.subjects`                                                                                    |
| `blocks.comments.options.maxBodyLength`, `extraColumns`                          | `blocks.messaging.options.maxBodyLength`, `extraColumns`                                             |
| `blocks.comments.options.documentSchema`                                         | removed                                                                                              |
| `blocks.comments.entities` (the `comment` entity)                                | the `message` entity, `blocks.messaging.entities`                                                    |
| `comment.mentions`, `comment.createdAt`                                          | `comment.mentionIds`, `comment.sentAt`                                                               |
| `commentsBlock.schemas`                                                          | removed; `commentInputSchema` and `commentChangeSchema` stay                                         |
| reactions on `{ type: "comment", id }`                                           | reactions on `{ type: "message", id }`                                                               |
| `edit_comment`, `delete_comment`, `comment_subject_readable`, `comment_authors`  | `edit_message`, `delete_message`, `can_subject(type, id, 'read')`                                    |
