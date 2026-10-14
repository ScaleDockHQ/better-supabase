---
"better-supabase": minor
---

Add the `templates` SQL module and the `better-supabase/blocks/templates` block: typed, versioned templates that create records. `createTemplates({ types })` takes a Standard Schema for each type's settings and body and an `apply` that creates the record. `apply(templateId, { into })` uses the newest published version, records which version made which record (`template.applied`), and starts the workflow-builder workflows attached to the template on the new record. System starters are kept by key with `sync(starters)`, and `fork(source, organizationId)` copies one into an organization with `forkedFrom`, `forkedFromVersion` and a `behind` flag. Each organization, type and language has at most one default.

`renderMergeFields(text, values, { escape })` and `defineMergeFields(subjectType, fields)` render `{{ field }}` placeholders with no dependencies, and `composeTemplateEmail` renders an email template for the notifications email channel. The `templates.apply` workflow step (`TEMPLATES_APPLY_STEP`, `templatesApplyStep`) creates recurring records from a scheduled workflow.

Workflow-builder versions can store an input JSON Schema: `versions.save(definition, graph, { inputSchema })` sets `input_schema`, which `WorkflowVersion.inputSchema` returns and a fork copies. `save_workflow_draft` takes a third `input_schema` argument. Templates check the inputs of the workflows they attach against it.
