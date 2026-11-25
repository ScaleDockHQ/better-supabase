---
"better-supabase": minor
---

`send_notification` accepts `actions` only from the service role and refuses them from a signed-in sender with `NOTIFICATION_ACTIONS_FORBIDDEN`. A button runs its operation for whoever presses it, so a member could otherwise send a colleague a one-click button that approves or pays on their behalf. Send notifications with actions from your server, and run `better-supabase upgrade` to regenerate the notifications module.
