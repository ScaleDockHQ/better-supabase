import type { BlockOf } from "../define-block.ts";
import type { FormsEvents, SignaturesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { formsEvents, signaturesEvents } from "./events.ts";
import { createForms } from "./forms.ts";
import { createSignatures } from "./signatures.ts";

/** The `forms` block's manifest (ADR 0029). */
export const formsBlock: BlockOf<"forms", typeof createForms, FormsEvents> =
  defineBlock({
    name: "forms",
    sql: ["forms"],
    options: {
      forms: optionKeys(["subjects", "handlers", "publicLimit"]),
    },
    events: formsEvents,
    create: createForms,
    client: "forms",
    category: "content",
  });

/** The `signatures` block's manifest (ADR 0029). */
export const signaturesBlock: BlockOf<
  "signatures",
  typeof createSignatures,
  SignaturesEvents
> = defineBlock({
  name: "signatures",
  sql: ["signatures"],
  options: {
    signatures: optionKeys(["subjects"]),
  },
  events: signaturesEvents,
  create: createSignatures,
  category: "content",
});
