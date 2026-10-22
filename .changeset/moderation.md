---
"better-supabase": minor
---

Add the `moderation` block: reports, a review queue, decisions and bans for any subject.

- `better-supabase add moderation` installs moderation items, reports, a decision log and bans per organization. Members report a subject for one of the configured `reasons`. At `autoHideThreshold` open reports (3 by default, 0 turns it off) the content is hidden until a moderator decides.
- `createModeration` from `better-supabase/blocks/moderation` reports content, reads the queue and one item with its reports and actions, decides (approve, hide, remove, restore, or ban, which removes the content and bans its author), reads the statuses of a list of subjects, and bans and unbans users. Decisions emit `moderation_item.decided`, reports emit `moderation_report.created`, and bans emit `moderation_ban.created` and `moderation_ban.lifted`. `moderationSection` shows a record's item on its page.
- With the messaging block, report a message or a comment as `{ type: "message", id }`. Hidden, removed and pending messages stay readable only to their author and moderators, removing a message empties it, and banned members can't send messages or comments.
- New permissions: `moderation.read`, `moderation.report`, `moderation.manage` and `moderation.ban`. Members get `moderation.report` by default.
