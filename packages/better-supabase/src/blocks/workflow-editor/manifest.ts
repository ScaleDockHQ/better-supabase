import type { BlockOf } from "../define-block.ts";
import type { WorkflowEditorEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { workflowEditorEvents } from "./events.ts";
import { workflowEditorSqlOptions } from "./options.ts";
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
  options: { "workflow-editor": workflowEditorSqlOptions },
  events: workflowEditorEvents,
  consumes: { workflows: "optional" },
  create: createWorkflowEditor,
  client: "workflow-editor",
  category: "automation",
  recipes: ["workflow-canvas"],
});
