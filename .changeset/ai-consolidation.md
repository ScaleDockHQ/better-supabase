---
"better-supabase": minor
---

The AI blocks share one run-state vocabulary, one sandbox table and one set of permission keys. Run `better-supabase sql upgrade` after updating: the ai-chat, ai-tasks, ai-providers and memory modules move to version 2. The [0.6 to 0.7 guide](https://bettersupabase.com/docs/migration/0.6-to-0.7) lists every rename.

- Runs end `completed`, `failed` or `cancelled` in ai-chat, ai-tasks and workflows. `RunState`, `FinalRunState` and `FINAL_RUN_STATES` from `better-supabase/blocks` name them. ai-chat still accepts `done`, `error` and `stopped` when a run is released, and stores the new names (deprecated until 0.8).
- `createAiChat(...).runs` has the run lookups; `createAiRuns` and the `runs` key of the durable chat context are deprecated.
- ai-chat owns `ai_sandboxes`. Harness sessions keep their sandbox there, and `createAiChat(...).sandboxes.idleStopJob` stops chat and harness sandboxes with one claim. `createAiProviders(...).sandboxes`, the sandbox types from `blocks/ai-providers`, `idleSandboxStop` and the ai-providers `idleAfter` option are deprecated aliases.
- ai-files, knowledge, memory, agents, connectors, ai-tasks and ai-providers check `ai.*` permission keys. Grants of the old `ai_chat.*` keys still pass until 0.8; ai-chat keeps its `ai_chat.*` keys.
- `MemoryScope` gains `project`, with `projectId` on namespaces and memory rows.
- eve sessions release runs with the new statuses, and the jobs page documents jobs cron, workflow schedules and ai-tasks as three scheduling layers.
- The eve, memory, ai-files, workflow-builder and ai-providers blocks keep their row decoders in `rows.ts`.
