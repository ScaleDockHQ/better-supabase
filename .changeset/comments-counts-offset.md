---
"better-supabase": minor
---

Comments gain counts and offset paging. `comments.counts(organizationId, subjectType, subjectIds)` returns the readable, non-deleted comments per subject (`comment_counts`), and `comments.list` takes `offset`. The `comments` module moves to version 2: `list_comments` takes `skip` as a sixth argument (`better-supabase sql upgrade` drops the five-argument one).
