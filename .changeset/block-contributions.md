---
"better-supabase": minor
---

Blocks declare what they give `approvals`, `bulk-actions`, `pipelines`,
`share-links` and `subjects` in a new `contributes` field, and those generic
blocks no longer name their consumers. A second instance contributes to the
generic instance its `uses` names. Two contributions with the same subject or
action name fail at render. Run `better-supabase upgrade` and `db diff`; the
rendered functions change only in the order of their branches.
