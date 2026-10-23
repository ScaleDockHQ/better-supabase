import type { BlockOf } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";
import { createIdentities } from "./identities.ts";
import { identitiesSqlOptions } from "./options.ts";

/** The `identities` block's manifest (ADR 0029). */
export const identitiesBlock: BlockOf<"identities", typeof createIdentities> =
  defineBlock({
    name: "identities",
    sql: ["identities"],
    options: { identities: identitiesSqlOptions },
    create: createIdentities,
    category: "identity",
  });
