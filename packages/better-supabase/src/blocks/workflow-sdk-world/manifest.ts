import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { workflowSdkWorldSqlOptions } from "./options.ts";

/** The `workflow-sdk-world` block's manifest (ADR 0029). */
export const workflowSdkWorldBlock: Block<"workflow-sdk-world"> = defineBlock({
  name: "workflow-sdk-world",
  sql: ["workflow-sdk-world"],
  options: {
    "workflow-sdk-world": workflowSdkWorldSqlOptions,
  },
  category: "operations",
});
