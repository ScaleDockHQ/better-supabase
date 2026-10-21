import type { BlockOf } from "../define-block.ts";
import type { FormsEvents, SignaturesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { formsEvents, signaturesEvents } from "./events.ts";
import { createForms } from "./forms.ts";
import { formsSqlOptions, signaturesSqlOptions } from "./options.ts";
import { createSignatures } from "./signatures.ts";

/** The `forms` block's manifest (ADR 0029). */
export const formsBlock: BlockOf<"forms", typeof createForms, FormsEvents> =
  defineBlock({
    name: "forms",
    sql: ["forms"],
    options: { forms: formsSqlOptions },
    events: formsEvents,
    create: createForms,
    client: "forms",
    category: "content",
    recipes: ["form-builder"],
  });

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
