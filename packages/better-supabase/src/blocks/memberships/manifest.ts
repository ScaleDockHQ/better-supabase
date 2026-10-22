import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { membershipsSqlOptions } from "./options.ts";

/** The `memberships` block's manifest (ADR 0029). */
export const membershipsBlock: Block<"memberships"> = defineBlock({
  name: "memberships",
  sql: ["memberships"],
  options: { memberships: membershipsSqlOptions },
  category: "tenancy",
  extension: "membershipsExtension",
});
