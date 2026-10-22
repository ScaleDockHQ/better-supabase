import type { BlockOf } from "../define-block.ts";
import type { SignaturesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { signaturesEvents } from "./events.ts";
import { signaturesSqlOptions } from "./options.ts";
import { createSignatures } from "./signatures.ts";

/** The `signatures` block's manifest (ADR 0029). */
export const signaturesBlock: BlockOf<
  "signatures",
  typeof createSignatures,
  SignaturesEvents
> = defineBlock({
  name: "signatures",
  sql: ["signatures"],
  options: { signatures: signaturesSqlOptions },
  events: signaturesEvents,
  create: createSignatures,
  category: "content",
});
