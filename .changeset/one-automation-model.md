---
"better-supabase": minor
---

One automation model. Automations, workflow action steps and sequence action steps run actions from
one registry: `defineAction` declares an action (`apiVersion: 1`, with an optional config schema)
and `createActionRegistry` collects them; `createRuleDispatcher` takes `{ actions }` instead of
`handlers`. The action hints are now `ACTION_UNKNOWN` and `ACTION_CONFIG_INVALID`.

`better-supabase/flows` is removed. Blocks ship default automations instead: the inbox opens a task
for each new conversation, hiring preboards each hired candidate and quotes orders each accepted
quote (turned off). Each organization gets its own copy, which it may turn off, edit or reset with
`resetDefault`. The conversions are actions of the target block (`taskFromConversationAction`,
`employeeFromApplicationAction`, `orderFromQuoteAction`). `createRuleSink` falls back to
`eventTarget(event)` when `load` returns nothing.

Workflow definitions lose their event triggers (`triggers.onEvent`, `builder.sink()`); an
automation's `workflow` action starts them. Block timers (SLA checks, sequence waits, AI schedules,
workflow schedules) run on the queue through `blockSchedules` and `blockTickHandler`. Doctor
BS418 names each removed API and its replacement.
