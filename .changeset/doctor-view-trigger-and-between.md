---
"better-supabase": minor
---

Doctor reports two more patterns that a declarative sync cannot keep stable. BS378 flags a `before` or `after` trigger aimed at a view, which never fires for the table under it. BS380 flags a check constraint that joins a `between` to other conditions with `and` or `or`, because Postgres reads it back as another expression and the next diff proposes the constraint again.
