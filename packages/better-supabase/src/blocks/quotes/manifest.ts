import type { BlockOf } from "../define-block.ts";
import type { QuotesEvents } from "./events.ts";

import { defineBlock, optionKeys } from "../define-block.ts";
import { quotesEvents } from "./events.ts";
import { createQuotes } from "./quotes.ts";

/** The `quotes` block's manifest (ADR 0029). */
export const quotesBlock: BlockOf<"quotes", typeof createQuotes, QuotesEvents> =
  defineBlock({
    name: "quotes",
    sql: ["quotes"],
    options: {
      quotes: optionKeys([
        "company",
        "contact",
        "prefix",
        "validDays",
        "extraColumns",
      ]),
    },
    events: quotesEvents,
    create: createQuotes,
    category: "crm",
  });
