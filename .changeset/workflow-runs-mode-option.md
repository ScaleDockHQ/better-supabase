---
"better-supabase": minor
---

`useWorkflowRuns` and `createWorkflowRunsController` take a `mode` option
(`live`, `test` or `all`, default `live`), so an editor can list the test runs
it starts instead of tracking their ids itself. `WorkflowRunMode` is exported
from `better-supabase/blocks/workflows`.
