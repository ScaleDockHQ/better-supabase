---
"better-supabase": minor
---

Workflow SDK runs start once per idempotency key, even when two starts race. The Supabase World claims the key in `workflow.workflow_run_keys` before it starts the run, and `startOnce(ctx, workflow, args, { key })` is `startFor` with a required key. `better-supabase/workflow-sdk` adds `cancelRuns` with a reason, `resumeStreamResponse` for streams a client reconnects to by chunk index, and `resumeHookFromWebhook`, which verifies a Stripe or Standard Webhooks callback and resumes the hook. The World gains `openHooks` (the hooks open runs wait on, without tokens) and `purgeRuns`.

Ended runs no longer have to stay forever: the `workflow-sdk` block's `retention` option (`"30 days"`) deletes them every hour with pg_cron, and `better-supabase db prune-workflows --older-than 30d` does it on demand. Run `better-supabase upgrade` and generate a migration for the new table and functions.
