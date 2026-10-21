import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { tenantSqlOptions } from "./options.ts";

/** The `tenant` block's manifest (ADR 0029). */
export const tenantBlock: Block<"tenant"> = defineBlock({
  name: "tenant",
  sql: ["tenant"],
  options: { tenant: tenantSqlOptions },
  category: "tenancy",
});
