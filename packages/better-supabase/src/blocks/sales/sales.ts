import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockContext } from "../create-blocks.ts";
import type { Deal } from "../deals/index.ts";
import type { CompositeOptions } from "../define-block.ts";
import type { Invoice } from "../invoices/index.ts";
import type { Order } from "../orders/index.ts";
import type { Quote } from "../quotes/index.ts";
import type { SalesClients, SalesParts } from "./parts.ts";

import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult as Async } from "../../core/result.ts";

/** What `sales.closeWon` returns: the won deal and the quote drafted from it. */
export interface ClosedWon {
  readonly deal: Deal;
  readonly quote: Quote | null;
}

/** What `sales.acceptQuote` returns. */
export interface AcceptedQuote {
  readonly quote: Quote;
  /** The deal it won, when `dealId` was given. */
  readonly deal: Deal | null;
  readonly order: Order | null;
  readonly invoice: Invoice | null;
}

/** What `sales.billQuote` returns. */
export interface BilledQuote {
  readonly invoice: Invoice;
  /** Whether it was issued, which `issue` asks for. */
  readonly issued: boolean;
}

/**
 * The helpers `sales` adds over its parts. Each calls the parts' hooked
 * clients, so app hooks on `deals`, `quotes`, `orders` and `invoices` see every
 * step. A step is idempotent on its own (`fromDeal`, `fromQuote` act once per
 * origin), so a retry after a failure in the middle finishes the chain.
 */
export interface Sales {
  /**
   * Wins the deal and, with `quote`, drafts its quote (once per deal). The deal
   * is won first, so a refused move leaves nothing behind.
   */
  closeWon(input: {
    dealId: string;
    note?: string | undefined;
    quote?: boolean | undefined;
  }): AsyncResult<ClosedWon>;
  /**
   * Loses the deal, then withdraws each quote in `withdraw` (the open quotes
   * the app lists for the deal) with the reason.
   */
  closeLost(input: {
    dealId: string;
    reason?: string | undefined;
    withdraw?: readonly string[] | undefined;
  }): AsyncResult<{ readonly deal: Deal; readonly withdrawn: number }>;
  /**
   * Records the customer's acceptance, wins the deal when `dealId` is given,
   * then orders or invoices the quote (`then`). A rejected quote does none of
   * it.
   */
  acceptQuote(input: {
    quoteId: string;
    dealId?: string | undefined;
    by?: string | undefined;
    note?: string | undefined;
    then?: "order" | "invoice" | undefined;
  }): AsyncResult<AcceptedQuote>;
  /**
   * The invoice of an accepted quote: the whole of it, or a deposit for
   * `depositBps` of it or a fixed `depositAmount`; `issue` issues the draft.
   */
  billQuote(input: {
    quoteId: string;
    depositBps?: number | undefined;
    depositAmount?: Money | undefined;
    issue?: boolean | undefined;
  }): AsyncResult<BilledQuote>;
}

/**
 * `closeWon` and `closeLost` over the clients of `deals` and `quotes`, which
 * `sales` and `crm` share.
 */
export function createDealClosers({
  deals,
  quotes,
}: Pick<SalesClients, "deals" | "quotes">): Pick<
  Sales,
  "closeWon" | "closeLost"
> {
  return {
    closeWon: ({ dealId, note, quote }) =>
      deals
        .win({ dealId, note })
        .andThen<ClosedWon>((deal) =>
          quote === true
            ? quotes
                .fromDeal(dealId)
                .map((drafted) => ({ deal, quote: drafted }))
            : Async.ok({ deal, quote: null }),
        ),

    closeLost: ({ dealId, reason, withdraw = [] }) =>
      deals.lose({ dealId, reason }).andThen((deal) =>
        Async.from(async () => {
          let withdrawn = 0;

          for (const quoteId of withdraw) {
            const result = await quotes.withdraw({
              quoteId,
              options: reason === undefined ? undefined : { reason },
            });

            if (!result.ok) {
              return result;
            }

            withdrawn += 1;
          }

          return { ok: true as const, data: { deal, withdrawn }, error: null };
        }),
      ),
  };
}

/** What the `sales` creator receives. */
export type SalesOptions = BlockContext &
  CompositeOptions<SalesParts> & {
    /** \`before\` and \`after\` hooks per method (ADR 0015). */
    readonly hooks?: NoInfer<BlockHooks<Sales>>;
    /** Receives the errors \`after\` hooks throw. Default: \`console\`. */
    readonly logger?: Logger;
  };

/** Creates the `sales` helpers over the clients of its parts. */
export function createSales(options: SalesOptions): Sales {
  const { deals, quotes, orders, invoices } = options.parts;

  const billQuote: Sales["billQuote"] = ({
    quoteId,
    depositBps,
    depositAmount,
    issue,
  }) =>
    invoices
      .fromQuote({
        quoteId,
        ...(depositBps === undefined ? {} : { depositBps }),
        ...(depositAmount === undefined ? {} : { depositAmount }),
      })
      .andThen<BilledQuote>((invoice) =>
        issue === true
          ? invoices
              .issue({ invoiceId: invoice.id })
              .map((issued): BilledQuote => ({ invoice: issued, issued: true }))
          : Async.ok({ invoice, issued: false }),
      );

  const client: Sales = {
    ...createDealClosers({ deals, quotes }),

    acceptQuote: ({ quoteId, dealId, by, note, then }) =>
      quotes
        .decide({
          quoteId,
          decision: "accepted",
          options: {
            ...(by === undefined ? {} : { by }),
            ...(note === undefined ? {} : { note }),
          },
        })
        .andThen<Pick<AcceptedQuote, "quote" | "deal">>((quote) =>
          dealId === undefined
            ? Async.ok({ quote, deal: null })
            : deals.win({ dealId, note }).map((deal) => ({ quote, deal })),
        )
        .andThen<AcceptedQuote>((so) =>
          then === "order"
            ? orders
                .fromQuote({ quoteId })
                .map(({ order }) => ({ ...so, order, invoice: null }))
            : then === "invoice"
              ? billQuote({ quoteId }).map(({ invoice }) => ({
                  ...so,
                  order: null,
                  invoice,
                }))
              : Async.ok({ ...so, order: null, invoice: null }),
        ),

    billQuote,
  };

  return withBlockHooks(client, options.hooks, {
    block: "sales",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
