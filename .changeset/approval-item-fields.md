---
"better-supabase": minor
---

Approval items take the columns your schema files add to `approval_items` as fields. Pass them as `fields` on an item in `approvals.request({ items })` and read them from `fields` on each item `get` returns. Upgrade: nothing to change for an app without such columns; run `better-supabase upgrade` to render the new reads and writes after you add one.
