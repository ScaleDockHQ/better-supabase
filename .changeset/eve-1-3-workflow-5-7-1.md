---
"better-supabase": minor
---

eve on Supabase moves to eve 1.3, Workflow 5.7.1 and the ai 7.0.179 line, finishes the purge of zero-retention runs through world-postgres 5.4.1's backstop, lets a web tier skip delivery with `skipWorkers`, and adds `supabaseSkillScopes` for eve's custom skills. The migration guide is [From 0.80 to 0.81](https://bettersupabase.com/docs/migration/0.80-to-0.81).

## Breaking changes

- Peer ranges: `eve >=1.3.0 <2`, `workflow >=5.7.1 <6`, `@workflow/world-postgres >=5.4.1 <5.5`, `ai >=7.0.179 <8`, `@ai-sdk/react >=4.0.183 <5` and `@ai-sdk/workflow >=2.0.111 <3`. `@workflow/world` stays at 5.3.0 and the World still speaks protocol 5.3.0.
- The `workflow-sdk` SQL module is at version 9. Run `better-supabase upgrade` before you deploy world-postgres 5.4.1: version 9 adds `workflow.add_job`, which takes the purge backstop world-postgres 5.4.1 adds when a zero-retention run ends, and `workflow_purge_backstops()`. Without it, the final write of a zero-retention run fails. In the `pg_net` and `vercel-queue` delivery modes it schedules `workflow_purge_backstops()` on pg_cron every minute; in poll mode the World runs it while it polls.
- `WorkflowMaintenance` has a new required member, `purgeBackstops({ batch? })`. The World implements it; a hand-written `WorkflowMaintenance` must add it.
- The World sets `GRAPHILE_WORKER_SCHEMA` to `workflow` when it is unset and warns when it names another schema, because no runner of the World reads that schema.

## Features

- `createSupabaseWorld({ skipWorkers: true })`, or `WORKFLOW_POSTGRES_SKIP_WORKERS=1`, starts, resumes, cancels and reads runs without polling or delivering, for a web tier next to separate workers.
- `supabaseSkillScopes()` from `better-supabase/eve` keys eve's experimental custom skills by tenant: personal, persona (read-only, chosen per turn from eve 1.3's turn id and parent session), channel and organization (writable by the roles in `writableBy`). Store the skills with `supabaseDocumentBackend({ memory, scope: "skills" })`.
