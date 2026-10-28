---
"better-supabase": minor
---

Status history records who made a change, memory scopes to records and expires, knowledge gets collections and system documents, the inbox keeps reply drafts, and workflows take the app's own node kinds and a default lifecycle workflow (ADRs 0123 to 0126).

- State machine: `transition(subject, to, { reason, actor })` records the actor's `name`, `email`, `ip` and `userAgent` in `status_history` (`actor_name`, `actor_email`, `ip`, `user_agent`), and `history()` returns them. An app history table maps them with `history.actorName`, `actorEmail`, `ip` and `userAgent`. `history: "app"` leaves the history to the app: the block checks edges and records `status.changed` but writes no history, and `history()` fails with `STATE_HISTORY_APP`.
- Memory: `{ scope: "record", subject }` keeps facts about one record that every member reads and admins change. `archival.upsert` and `saveExtracted` take `category`, `confidence` (weighs search scores) and `expiresAt`. Searches count `useCount` and `lastUsedAt`. `archival.restore(id)` undoes a forget, and `archival.purge({ retentionDays, batch })` (service role) removes deleted and expired facts.
- Knowledge: `knowledge.collections` creates collections with a visibility (`automatic`, `restricted`, `disabled`) and a priority, and grants restricted ones to users or teams. Documents take `collectionId`; `documents.list` and `search` filter by collection, and search ranks higher priority collections first. `documents.create(null, ...)` and `ingest.text(null, ...)` (service role) create system documents every organization reads.
- Inbox: `inbox.drafts` keeps a staff member's reply draft per conversation (`upsert`, `list`, `send`, `discard`), and `suggest` (service role) files an AI draft every staff member who can reply sees.
- Workflow editor: `defineNodeKind` defines the app's own node kinds (`apiVersion: 1`), `createWorkflowEditor({ nodes })` and `nodeKinds.sync()` register them in `workflow_node_kinds`, and `nodeKinds.list()` returns them. `executeGraph` runs custom nodes through `runtime.node`, and `graphStarter({ nodeKinds, nodes })` binds one step per kind. Definitions take a `purpose` (`automation` or `lifecycle`) and `isDefault`; `definitions.setPurpose` sets them and `definitions.resolve(tenant, { subjectType })` returns the default lifecycle workflow's published version.

Run `better-supabase upgrade` and generate a migration: state-machine moves to version 3, memory to 3, knowledge to 3, inbox to 6 and workflow-editor to 4. `better-supabase codemod 0.35` rewrites the call sites marked below.

Breaking changes:

- `transition(subject, to, reason)` takes `{ reason, actor }` as its third argument; the codemod rewrites a string literal reason and lists the rest. The SQL `transition` takes a trailing `actor jsonb`.
- `memory.archival.forget` soft deletes: the fact leaves lists and searches but stays until `purge` removes it. Schedule `purge`.
- `KnowledgeDocument.organizationId` and `ownerId` are `string | undefined`, undefined for a system document.
- `validateGraph(graph, steps)` is `validateGraph(graph, { steps, nodes })`; the codemod rewrites it. `WorkflowNodeKind` accepts any kind name, so a map over every kind keys by the new `WorkflowBuiltinNodeKind` and falls back for custom kinds. A graph with a kind that is neither built in nor registered fails `validate_workflow_graph`.
- `WorkflowDefinition` has `purpose` and `isDefault`.
