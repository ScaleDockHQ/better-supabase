import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { dataApiGrantsSqlOptions } from "./options.ts";

/** The `grants` block's manifest (ADR 0029). */
export const dataApiGrantsBlock: Block<"data-api-grants"> = defineBlock({
  name: "data-api-grants",
  sql: ["data-api-grants"],
  options: { "data-api-grants": dataApiGrantsSqlOptions },
  category: "identity",
});
