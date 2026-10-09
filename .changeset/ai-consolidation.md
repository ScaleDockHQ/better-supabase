---
"better-supabase": minor
---

The AI blocks share one run-state vocabulary, one sandbox table and one set of permission keys. The ai-chat, ai-tasks, ai-providers and memory modules move to version 2; `better-supabase sql upgrade` brings a database installed from an earlier build forward.

- Runs end `completed`, `failed` or `cancelled` in ai-chat, ai-tasks and workflows. `RunState`, `FinalRunState` and `FINAL_RUN_STATES` from `better-supabase/blocks` name them.
- `createAiChat(...).runs` has the run lookups, and durable chats read them from the context's `chats`.
- ai-chat owns `ai_sandboxes`. Harness sessions keep their sandbox there, and `createAiChat(...).sandboxes.idleStopJob` stops chat and harness sandboxes with one claim. Set the idle time with `sql.modules.ai-chat.options.sandboxIdleAfter`.
- ai-files, knowledge, memory, agents, connectors, ai-tasks and ai-providers check `ai.*` permission keys. ai-chat keeps its `ai_chat.*` keys, and the default roles grant both.
- `MemoryScope` gains `project`, with `projectId` on namespaces and memory rows.
- eve sessions release runs with the new statuses, and the jobs page documents jobs cron, workflow schedules and ai-tasks as three scheduling layers.
- The eve, memory, ai-files, workflow-builder and ai-providers blocks keep their row decoders in `rows.ts`.
