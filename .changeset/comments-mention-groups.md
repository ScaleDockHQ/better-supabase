---
"better-supabase": minor
---

`sql.modules.comments.options.mentionGroups: { table, group, member, tenant? }` expands a mentioned group id (a team, say) into its members before the mention notification is sent. The author is left out, every expanded member must pass the same read check as a directly mentioned user, an edit notifies only members not already reached through the old mentions, and `comment.mentioned` carries the expanded user ids. Without the option the module renders the same SQL as before.
