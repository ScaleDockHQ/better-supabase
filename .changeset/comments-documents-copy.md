---
"better-supabase": minor
---

The comments block keeps a rich-text `document` (jsonb) next to the plain-text `body`, with `createComments({ mentionsOf })` to read mentions from it and `options.documentSchema` for a pg_jsonschema check. `options.subjects.<type>.cascade` writes an `after delete` trigger that deletes a subject's comments with the subject row. `comments.copy()` (`copy_comments`, service role) copies a thread to another subject with its authors and replies, and `comments.history()` (`list_activity`) reads the activity feed or one subject's timeline as the caller. `create_comment` and `edit_comment` take the new arguments; the old overloads are dropped.
