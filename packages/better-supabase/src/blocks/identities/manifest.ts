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
    entities: { identity: { mutability: "read-only" } },
    description:
      "Links an email address or a chat user to an app user or a contact. Rows come only from a one-time code the signed-in user issues and the service redeems, or from a confirmed address in auth.users.",
  });
