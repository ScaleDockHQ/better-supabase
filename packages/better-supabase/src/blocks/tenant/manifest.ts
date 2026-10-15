import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `tenant` block's manifest (ADR 0029). */
export const tenantBlock: Block<"tenant"> = defineBlock({
  name: "tenant",
  sql: ["tenant"],
  options: {
    tenant: optionKeys(["claimFormat", "roleThrough", "sameTenant"]),
  },
  category: "foundation",
});
