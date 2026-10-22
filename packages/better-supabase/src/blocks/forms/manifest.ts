import type { BlockOf } from "../define-block.ts";
import type { FormsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { formsEvents } from "./events.ts";
import { createForms } from "./forms.ts";
import { formsSqlOptions } from "./options.ts";

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
