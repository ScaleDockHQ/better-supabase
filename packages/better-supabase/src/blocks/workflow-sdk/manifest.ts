import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { workflowSdkSqlOptions } from "./options.ts";

/** The `workflow-sdk` block's manifest (ADR 0029). */
export const workflowSdkBlock: Block<"workflow-sdk"> = defineBlock({
  name: "workflow-sdk",
  sql: ["workflow-sdk"],
  options: { "workflow-sdk": workflowSdkSqlOptions },
  category: "automation",
});
