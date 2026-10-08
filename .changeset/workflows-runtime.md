---
"better-supabase": minor
---

Adds durable workflows. The `workflows` SQL module and `better-supabase/blocks/workflows` record the runs of any engine in `workflow_runs`, which members read through RLS. They also add cron schedules, semaphores and admission control, and `useWorkflowRuns` and `useWorkflowRun` in `better-supabase/blocks/workflows/react`. `better-supabase/workflow-sdk/world` is a Workflow SDK World on Supabase (Node only), with poll or pg_net delivery and per-run encryption keys from Vault. Its default export is `createWorld()`. It comes with the `workflow-sdk-world` SQL module. `better-supabase/workflow-sdk` adds `startFor`, `workflowStarter`, `startOnEvent`, `authorizeHook`, `hookMetadata` and `protectWebHandler`.
