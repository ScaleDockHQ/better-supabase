import type { BlockOf } from "../define-block.ts";
import type { SignaturesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { signaturesEvents } from "./events.ts";
import { signaturesSqlOptions } from "./options.ts";
import { signaturesBinding } from "./record-binding.ts";
import { createSignatures } from "./signatures.ts";

/** The `signatures` block's manifest (ADR 0029). */
export const signaturesBlock: BlockOf<
  "signatures",
  typeof createSignatures,
  SignaturesEvents,
  Record<never, never>,
  never,
  typeof signaturesBinding
> = defineBlock({
  name: "signatures",
  sql: ["signatures"],
  options: { signatures: signaturesSqlOptions },
  events: signaturesEvents,
  record: signaturesBinding,
  create: createSignatures,
  category: "content",
  entities: {
    signature_request: {
      mutability: "state-machine",
      emits: { create: false },
    },
  },
  description:
    "Simple electronic signatures on a frozen version of a record: drawn, typed or click signatures in parallel or in order, a hash that detects edits after signing, and an approval step a signer can decide.",
});
