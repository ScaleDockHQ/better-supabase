---
"better-supabase": minor
---

New `tasks.assignToMe({ workItemId, userId })`: it adds the user to the assignees and keeps the others. The caller passes the user id because the client has no signed-in user.
