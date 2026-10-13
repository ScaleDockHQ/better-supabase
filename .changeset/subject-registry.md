---
"better-supabase": minor
---

Add `config.subjects`, an app-wide subject registry. Modules that take `subjects` (tags, comments, attachments, reminders and the others) use the registered types when their own option is unset, accept a list of registered names, and merge an object entry onto the registered one. The new `subjects` SQL module writes `subject_title`, `subject_url` and `can_subject`, which run as the caller. `gen` emits `subjectTypes`, `SubjectType` and `SubjectRef`, and doctor reports a registered table or column the database lacks (BS331) and a registered table without RLS (BS332).
