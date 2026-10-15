import type { Block } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";

/** The `access` block's manifest (ADR 0029). */
export const accessBlock: Block<"access"> = defineBlock({
  name: "access",
  sql: ["access"],
  options: {
    access: optionKeys(["platformRoleScope", "scope", "tenantRoleScope"]),
  },
  category: "foundation",
});
