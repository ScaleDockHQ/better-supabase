import type { Block } from "../define-block.ts";

import { defineBlock } from "../define-block.ts";

/** The `mfa` block's manifest (ADR 0029). */
export const mfaBlock: Block<"mfa"> = defineBlock({
  name: "mfa",
  sql: ["mfa"],
  category: "identity",
  entities: { mfa: { mutability: "read-only" } },
  description:
    "mfa_satisfied() for restrictive policies: true when the caller has no verified factor, or verified one in this session (aal2).",
  recipes: ["mfa-setup"],
});
