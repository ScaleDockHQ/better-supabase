import type { BlockOf } from "../define-block.ts";
import type { WorkflowEditorEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workflowEditorEvents } from "./events.ts";
import { createWorkflowEditor } from "./workflow-editor.ts";

/** The `workflow-editor` block's manifest (ADR 0029). */
export const workflowEditorBlock: BlockOf<
  "workflow-editor",
  typeof createWorkflowEditor,
  WorkflowEditorEvents,
  { readonly workflows: "optional" }
> = defineBlock({
  name: "workflow-editor",
  sql: ["workflow-editor"],
  events: workflowEditorEvents,
  consumes: { workflows: "optional" },
  create: createWorkflowEditor,
  client: "workflow-editor",
  category: "automation",
  description:
    "Workflow definitions a tenant edits as an engine-neutral node graph, with draft, published and archived versions, triggers (webhook tokens stored hashed), credential references a CredentialProvider resolves, a synced step library, per-node run status pinged on the run's topic, and failed and slow alerts written as workflow_alert.triggered outbox events.",
  recipes: ["workflow-canvas"],
});
