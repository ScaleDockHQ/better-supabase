---
"better-supabase": minor
---

Incoming webhook endpoints can belong to a record: `sql.modules.webhooks-in.options.subjects` maps subject types to tables (with `id`, `tenant`, `permission` and `cascade`, as for comments), `hooks.create({ subject })` checks that the subject exists in the tenant, the read policy hides endpoints whose subject the caller can't read, and `cascade: true` deletes a subject's endpoints with it. `hooks.list(tenant, subject?)` (`list_incoming_webhooks`) lists endpoints without secrets as the caller. `create_incoming_webhook` takes `subject_type` and `subject_id`; the old overload is dropped.
