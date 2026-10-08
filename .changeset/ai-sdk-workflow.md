---
"better-supabase": minor
---

`better-supabase/ai-sdk/workflow` runs chat answers as Workflow SDK workflows, with `@ai-sdk/workflow` (2) as a new optional peer. `durableChat` serves the start, reconnect (`startIndex`), stop and approval routes with the `x-workflow-run-id` header, and `durableTurn` runs the agent inside a `"use workflow"` function: it saves the answer after each pass, stores approvals in `ai_tool_approvals` and waits on a hook until they are decided, and stops through a stop hook. `runDurableStep`, `durableSteps` and `saveMessagesStep` are the turn's database steps. `useDurableAssistant` and `durableTransport` in `better-supabase/ai-sdk/workflow/react` are the client half.

The `ai-chat` SQL module adds `ai_run_steps` for the progress of long runs, the engine's run id on `ai_runs` (`external_run_id`), and the experimental `ai_harness_sessions` store for coding-agent harnesses. `createAiRuns` reads runs, records steps and lists the caller's pending approvals; `createHarnessSessions` loads, saves and locks harness sessions; `idleSandboxStop` is a job handler that stops idle sandboxes. The `ai-files` filename check is written without `between` so schema diffs converge.

The `ai` catalog pin moves to 7.0.131 and `@ai-sdk/react` to 4.0.134, the versions `@ai-sdk/workflow` 2.0.63 needs.
