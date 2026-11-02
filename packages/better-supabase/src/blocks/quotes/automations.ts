import type { DefaultAutomation } from "../../core/automation.ts";

/**
 * Orders each accepted quote through the `orders.from_quote` action, whose
 * order creation the app supplies (`orderFromQuoteAction`). Ships turned off
 * when orders is installed.
 */
export const QUOTE_TO_ORDER: DefaultAutomation = {
  key: "quotes.quote_to_order",
  name: "Order each accepted quote",
  description:
    "Creates an order for the accepted quote, linked created_from the quote, so an accepted quote orders once.",
  trigger: "quote.accepted",
  subjectType: "quote",
  actions: [{ kind: "orders.from_quote" }],
  enabled: false,
  requires: ["orders"],
};

/**
 * Drafts a quote for each won deal through `quotes.from_deal`. Ships turned off
 * when deals is installed.
 */
export const DEAL_TO_QUOTE: DefaultAutomation = {
  key: "quotes.deal_to_quote",
  name: "Draft a quote for each won deal",
  description:
    "Creates a draft quote for the won deal, linked created_from the deal, so a won deal drafts one quote.",
  trigger: "deal.closed",
  subjectType: "deal",
  actions: [{ kind: "quotes.from_deal" }],
  enabled: false,
  requires: ["deals"],
};

/** The automations the quotes block ships. */
export const QUOTES_AUTOMATIONS: readonly DefaultAutomation[] = [
  QUOTE_TO_ORDER,
  DEAL_TO_QUOTE,
];
