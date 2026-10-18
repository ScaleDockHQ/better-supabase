import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `mfa` block's manifest (ADR 0029). */
export const mfaBlock: Block<"mfa"> = defineBlock({
  name: "mfa",
  sql: ["mfa"],
  category: "identity",
  recipes: ["mfa-setup"],
});
