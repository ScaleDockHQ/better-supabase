---
"better-supabase": minor
---

The `workflow-editor` and `inbox` blocks gain list pages, and `workflows` gains a
definition filter. `workflow-editor` adds `definitions.page`, `facets`, `count`
and `getDefinition`, with `q` over the name and the slug, a `state` filter
(`published`, `draft`, `new`) and the sorts `name`, `updatedAt` and `createdAt`.
`inbox` adds `inboxes.page`, `facets`, `count` and `getInbox`, and
`templates.page`, `facets`, `count` and `getTemplate`. `conversations.page`
gains the filters `priority`, `sla`, `slaMinutes` and `tagId` (the last needs the
`tags` block) and the facets `priority` and `sla`. `workflows.runs.list` takes
`definitionId`, one builder definition id or a list, which the database applies
to the runs' `bsb.definition` attribute.

All of it is additive. `definitions.list` and `definitions.get` stay as
deprecated aliases. The new SQL functions are `page_workflow_definitions`,
`page_inboxes`, `get_inbox`, `page_message_templates`, `get_message_template`
and `inbox_conversation_tagged`, and `workflow_runs_list` gains a
`definition_ids` argument (its old signature is replaced). Run
`better-supabase upgrade` and apply the migration it generates. A hand-written
implementation of the `WorkflowEditor` or `Inbox` interface needs the new
methods.
