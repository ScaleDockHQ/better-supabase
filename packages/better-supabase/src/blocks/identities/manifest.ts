import type { BlockOf } from "../define-block.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { createIdentities } from "./identities.ts";

/** The `identities` block's manifest (ADR 0029). */
export const identitiesBlock: BlockOf<"identities", typeof createIdentities> =
  defineBlock({
    name: "identities",
    sql: ["identities"],
    options: {
      identities: optionKeys(["codeMinutes", "verifiedEmails"]),
    },
    create: createIdentities,
    category: "foundation",
  });
