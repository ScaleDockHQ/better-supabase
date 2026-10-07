---
"better-supabase": minor
---

Comment subjects take per-action permissions: `sql.modules.comments.options.subjects.<type>.permissions: { read, create, moderate }` replaces the module's `comments.read`, `comments.create` and `comments.moderate` keys for that subject type in the comment policies, so each subject's threads follow its own permissions.
