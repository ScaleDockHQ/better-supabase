import type { BlockOf } from "../define-block.ts";
import type { QuotesEvents } from "./events.ts";

import { blockLink } from "../composition.ts";
import { defineBlock } from "../define-block.ts";
import { quoteFromDealFactory } from "./actions.ts";
import { QUOTES_AUTOMATIONS } from "./automations.ts";
import { quotesEvents } from "./events.ts";
import { quotesSqlOptions } from "./options.ts";
import { createQuotes } from "./quotes.ts";
import { quotesBinding } from "./record-binding.ts";

/** The `quotes` block's manifest (ADR 0029). */
export const quotesBlock: BlockOf<
  "quotes",
  typeof createQuotes,
  QuotesEvents,
  Record<never, never>,
  never,
  typeof quotesBinding
> = defineBlock({
  name: "quotes",
  sql: ["quotes"],
  options: { quotes: quotesSqlOptions },
  events: quotesEvents,
  create: createQuotes,
  record: quotesBinding,
  category: "crm",
  importTarget: ["quote"],
  entities: {
    quote: {
      mutability: "editable",
      idempotent: ["create"],
      emits: { create: true, update: true },
    },
  },
  links: [
    blockLink(
      "fromDeal",
      "conversion",
      "quote",
      "deals",
      "deal",
      "quote_from_deal",
    ),
  ],
  concerns: ["lifecycle", "search"],
  description:
    "Quotes with sections, optional lines, discounts, prices with or without tax, tax per rate and a deposit; published versions; a public link or the signed-in portal the customer accepts, rejects or asks changes through; expiry; and quotes from deals. With catalog, a line that names a product variant takes its price and title.",
  recipes: ["quote-builder"],
  actions: [
    { kind: "quotes.from_deal", title: "Draft a quote for the won deal" },
  ],
  handlers: { "quotes.from_deal": quoteFromDealFactory },
  automations: QUOTES_AUTOMATIONS,
});
