---
"better-supabase": minor
---

App tables emit outbox events, and rules and the workflow builder react to them (ADR 0048).

- `appTables.<name>.events` (`true` or `{ on, include }`) adds a trigger that writes `<type>.created`, `<type>.updated` and `<type>.deleted` to the outbox in the same transaction as the write. The payload is an `AppTableEventData` with the id, the tenant, the subject, the `include` columns and, on update, the changed columns. It needs the outbox block. `gen blocks` writes `appTableEvents`, a typed event map.
- `createRuleSink` runs the rules for each outbox event and dispatches their actions, and `WorkflowBuilder.sink()` starts the event triggers that match.
- Rules get the built-in handlers `notifyAction`, `setFieldAction`, `webhookAction` and `workflowAction`.
- A change to `events` is the safe design change `table.events`, and a design with `events` is format 4.

`gen` tags `appTableEvents` and `appTableEventSchemas` with `@public`, so Knip doesn't report the one an app leaves unused.
