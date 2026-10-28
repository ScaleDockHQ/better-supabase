# 0126: A registry of the app's own workflow node kinds; lifecycle definitions with a default

- Status: accepted
- Date: 2026-10-28

## Context

The workflow builder accepted five node kinds (`trigger`, `step`, `sleep`,
`approval`, `condition`), fixed in TypeScript and in the SQL graph check.
Apps that wanted a node of their own, such as a scoring check with two
branches or a notification with its own config form, had to squeeze it into
a `step` and lost the palette entry, the config schema and branching.

Apps that drive records through stages with a workflow also need to know
which workflow to run for a new record. Each app kept that mapping in its
own table.

## Decision

`workflow_node_kinds` registers the app's own kinds: a lowercase name, a
title, a description, whether it branches and a config schema. Apps define
them with `defineNodeKind` (`apiVersion: 1`) and write them with
`sync_workflow_node_kinds` (service role); `validate_workflow_graph` accepts a
registered kind and allows branches only from a branching kind.
`validateGraph(graph, { steps, nodes })` does the same in TypeScript and runs
each kind's `validate`. The engine runs a custom node as a step:
`executeGraph` calls `runtime.node`, and `compileGraph` gives each custom node
a step alias that `graphStarter({ nodeKinds, nodes })` binds by kind. A
branching kind takes the `true` branch when its output is truthy. Kind names
can't shadow a built-in kind.

Definitions gain `purpose` (`automation` or `lifecycle`) and `is_default`.
`set_workflow_definition_purpose` (admin) makes a lifecycle definition the
default and clears the flag on the tenant's other defaults that share a
subject type. `resolve_workflow_definition(tenant, purpose, subject_type)`
returns the published version of the matching default, the tenant's own
before a system default it hasn't opted out of. The workflow-editor block
moves to version 4.

## Alternatives considered

- A `run` function on the node definition. Rejected: the graph runs inside
  the Workflow SDK's VM, where only steps may do I/O, so the engine has to
  call a step anyway.
- Purpose and default on versions. Rejected: a version is immutable once
  published, and the default is a choice about the definition.

## Consequences

`WorkflowNodeKind` is any kind name now; code that keys a map by it uses
`WorkflowBuiltinNodeKind` with a fallback. `validateGraph(graph, steps)`
becomes `validateGraph(graph, { steps })`, which the 0.35 codemod rewrites.
A graph with an unregistered custom kind fails to publish.
