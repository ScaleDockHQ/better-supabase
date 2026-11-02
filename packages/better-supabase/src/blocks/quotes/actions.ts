import type { Action, ActionFactory } from "../../core/automation.ts";
import type { Result } from "../../core/result.ts";
import type { ConversionClients } from "../automations/conversion.ts";

import { ok } from "../../core/result.ts";
import {
  defineConversionAction,
  narrowClients,
} from "../automations/conversion.ts";

/** `blocks.quotes` and `blocks.relations` for one organization. */
export interface QuoteFromDealClients extends ConversionClients {
  readonly quotes: {
    fromDeal(dealId: string): PromiseLike<Result<{ readonly id: string }>>;
  };
}

export interface QuoteFromDealOptions {
  /** The clients for one organization, over a service connection. */
  readonly clients: (
    tenant: string,
  ) => QuoteFromDealClients | PromiseLike<QuoteFromDealClients>;
}

/**
 * The `quotes.from_deal` action, which the deals default automation runs on
 * `deal.closed`: a draft quote from a won deal, once per deal. A lost deal is
 * skipped.
 */
export function quoteFromDealAction(options: QuoteFromDealOptions): Action {
  return defineConversionAction<QuoteFromDealClients, undefined, undefined>({
    kind: "quotes.from_deal",
    title: "Draft a quote for the won deal",
    targetType: "quote",
    clients: options.clients,
    source: (context) =>
      context.payload?.["outcome"] === "won"
        ? { type: context.subjectType, id: context.subjectId }
        : undefined,
    map: () => undefined,
    linksItself: true,
    create: (_, context) =>
      context.clients.quotes
        .fromDeal(context.source.id)
        .then((result) => (result.ok ? ok({ id: result.data.id }) : result)),
  });
}

/** The `quotes.from_deal` factory for the action registry. */
export const quoteFromDealFactory: ActionFactory = ({ clients }) =>
  quoteFromDealAction({
    clients: narrowClients<QuoteFromDealClients>(
      "quotes.from_deal",
      ["relations.link", "relations.convertedInto", "quotes.fromDeal"],
      clients,
    ),
  });
