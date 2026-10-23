import type { BlockOf } from "../define-block.ts";
import type { QuotesEvents } from "./events.ts";

import { defineBlock } from "../define-block.ts";
import { QUOTES_AUTOMATIONS } from "./automations.ts";
import { quotesEvents } from "./events.ts";
import { quotesSqlOptions } from "./options.ts";
import { createQuotes } from "./quotes.ts";

/** The `quotes` block's manifest (ADR 0029). */
export const quotesBlock: BlockOf<"quotes", typeof createQuotes, QuotesEvents> =
  defineBlock({
    name: "quotes",
    sql: ["quotes"],
    options: { quotes: quotesSqlOptions },
    events: quotesEvents,
    create: createQuotes,
    category: "crm",
    recipes: ["quote-builder"],
    automations: QUOTES_AUTOMATIONS,
  });
