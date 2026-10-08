---
"better-supabase": minor
---

Adds the workflow builder. The `workflow-builder` SQL module and `better-supabase/blocks/workflow-builder` store graph workflows per tenant: definitions, versions that the database checks before it publishes them, webhook, schedule and event triggers, credentials by `credential_ref`, a step library, the status of each node of a run, and alerts on failed or slow runs. `better-supabase/blocks/workflow-builder/react` adds `useWorkflowBuilder` and `useWorkflowCanvasRun`. `better-supabase/workflow-sdk/builder` compiles a graph to Workflow SDK dynamic source with `compileGraph`, starts runs with `graphStarter` (falling back to a static executor that calls `executeGraph`), and records node status with `nodeRunReporter`. The new permissions are `workflow.edit` and `workflow.publish`.
