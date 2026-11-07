---
"better-supabase": minor
---

The notifications block deletes a subject's notifications and subscriptions when the subject row is deleted, for every app table in `config.subjects`, without a `blocks.notifications.on` entry. Set `on` to choose the types yourself.
