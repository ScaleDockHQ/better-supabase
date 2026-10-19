---
"better-supabase": minor
---

A workflow-builder `condition` node can test a filter tree: `config: { filter, fields }`, where `filter` is a `FilterQuery` (the format of list filters and the rules block) and each field's `id` is the path it reads under `input`, `results` or `subject`. The single-path form (`{ path, op, value }`) keeps working. Event triggers take the same shape in `config.when`, over `type`, `tenant` and `payload...`: `triggers.onEvent` skips a trigger whose `when` doesn't match, and `triggers.save` refuses one it can't use with `invalid_input`. New exports: `filterConditionOf`, `matchesFilter`, `triggerMatches` and the types `WorkflowFilterCondition`, `WorkflowFilterField`, `WorkflowNodeCondition` and `TriggerEvent`. `conditionOf` now returns a `WorkflowNodeCondition`.
