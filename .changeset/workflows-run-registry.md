---
"better-supabase": minor
---

The `workflows` run registry takes an idempotency key and a dispatch lease (module version 4), accepts run extra columns through `blocks.workflows.options.runExtraColumns`, and installs without schedules, semaphores or start requests when those tables are mapped to `null`. `startOnce` in `better-supabase/workflow-sdk` accepts `registry: workflows.runs` and throws `WorkflowRunKeysMissingError` (`WORKFLOW_RUN_KEYS_MISSING`) when it has neither a registry nor World run keys. The resume route maps a missing hook to 404 and other engine failures to 503 or 500.
