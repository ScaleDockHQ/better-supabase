import type { BlockOf } from "../define-block.ts";
import type { FormsEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { formsEvents } from "./events.ts";
import { createForms } from "./forms.ts";
import { formListSurface } from "./lists.ts";
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
    entities: {
      form: {
        ...formListSurface,
        mutability: "editable",
        emits: { create: true, update: false },
      },
    },
    concerns: ["lifecycle", "search"],
    description:
      "Forms with numbered versions (steps and show or skip logic), a JSON Schema 2020-12 per version that validates every submission, drafts, public links through share-links with a rate limit and a bot-check hook, handlers that turn a submission into a record, scoring against an answer key respondents can't read, and NPS rollups.",
    recipes: ["form-builder"],
  });
