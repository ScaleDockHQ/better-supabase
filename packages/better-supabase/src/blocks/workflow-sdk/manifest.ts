import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { workflowSdkSqlOptions } from "./options.ts";

/** The `workflow-sdk` block's manifest (ADR 0029). */
export const workflowSdkBlock: Block<"workflow-sdk"> = defineBlock({
  name: "workflow-sdk",
  sql: ["workflow-sdk"],
  options: { "workflow-sdk": workflowSdkSqlOptions },
  category: "automation",
  entities: { workflow_sdk: { mutability: "read-only" } },
  description:
    "The tables of the Workflow SDK World (@workflow/world-postgres 5.2.0) in the workflow schema, closed to the API roles; a trigger that copies each run into workflow_runs, a pg_net dispatcher for the delivery queue on a pg_cron schedule, start idempotency keys, a list of the hooks open runs wait on and a purge of ended runs.",
});
