---
"better-supabase": minor
---

The `workflows` and `workflow-builder` SQL modules record durable workflow runs and store graph workflows per tenant.

- `better-supabase/blocks/workflows` records the runs of any engine in `workflow_runs` with cron schedules, semaphores and admission control, and `useWorkflowRuns` and `useWorkflowRun` in `/blocks/workflows/react` read them.
- `better-supabase/workflow-sdk/world` is a Workflow SDK World on Supabase (Node only, `createWorld()`, the `workflow-sdk-world` module), and `better-supabase/workflow-sdk` adds `startFor`, `workflowStarter`, `startOnEvent`, `authorizeHook`, `hookMetadata` and `protectWebHandler`.
- `better-supabase/blocks/workflow-builder` stores definitions, checked versions, triggers, credentials by `credential_ref`, a step library, node status and alerts, with `useWorkflowBuilder` and `useWorkflowCanvasRun`. `better-supabase/workflow-sdk/builder` adds `compileGraph`, `graphStarter` and `nodeRunReporter`. The new permissions are `workflow.edit` and `workflow.publish`.
- Only the service role stores a version's compiled form (`createBuilder` writes it through `service`), and `graphStarter` compiles from the graph on every start. Node ids are 1 to 100 letters, digits, `_` or `-`.
- The World refuses unsigned poll deliveries outside development and test, fails closed on a Vault read error, aborts a delivery after `deliveryTimeout` (300 s), and mirrors a run's tenant only when its actor holds `workflow.run` there.
