---
"better-supabase": minor
---

`better-supabase/workflow-sdk/world` speaks the `@workflow/world` 5.2
protocol (`WORKFLOW_WORLD_PROTOCOL` is `5.2.0`), so the peer ranges are now
`workflow` `>=5.5.0 <6` and `@workflow/world` and `@workflow/world-postgres`
`>=5.2.0 <5.3`; `@vercel/functions` starts at 3.11.1, the release
`@workflow/core` 5.5 depends on. The `workflow-sdk` SQL module is version 5:
it adds the `workflow.workflow_job_lock_holders` table of world-postgres
migration 0030, closed to the API roles. Run `better-supabase upgrade` and
apply its migration before you deploy. The World declares
`queueAuthMode: "skip"`, because its flow route already checks the HMAC
signature of every delivery, and keeps the world-postgres capabilities, so
`WORKFLOW_SPEC_VERSION=9` can create spec 9 runs. See the 0.66 to 0.67 guide.
