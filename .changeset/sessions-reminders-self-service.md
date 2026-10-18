---
"better-supabase": minor
---

Users can now manage their own sessions and reminders. The `sessions` module adds `list_my_sessions()` and `end_my_session(id)`, which list the caller's unexpired sessions (with the current one marked) and end one of them. The `reminders` module adds `list_my_reminders` and `delete_reminder`, and the reminders client adds `list(organizationId, subjectType, subjectId)` and `remove(id)`. Run `better-supabase sql sync` and generate a migration to install the new functions.
