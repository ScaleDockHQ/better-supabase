import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createLinkedIdentities } from "./linked-identities.ts";
import { linkedIdentitiesSqlOptions } from "./options.ts";

/** The `identities` block's manifest (ADR 0029). */
export const linkedIdentitiesBlock: BlockOf<
  "linked-identities",
  typeof createLinkedIdentities
> = defineBlock({
  name: "linked-identities",
  sql: ["linked-identities"],
  options: { "linked-identities": linkedIdentitiesSqlOptions },
  create: createLinkedIdentities,
  category: "identity",
});
