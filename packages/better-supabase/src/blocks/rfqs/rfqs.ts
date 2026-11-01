import type { Money } from "../../commerce/money.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult as AsyncResultType } from "../../core/result.ts";
import type { BlockOptions } from "../shared.ts";

import { money } from "../../commerce/money.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  RFQ_QUOTE_STATUSES,
  RFQ_STATUSES,
  RFQ_SUPPLIER_STATUSES,
} from "../../sql/modules/rfqs-values.ts";
import {
  applyTemporal,
  bigintOf,
  blockCall,
  enumOrThrow,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

/** Where a request for quotation stands. */
export type RfqStatus = (typeof RFQ_STATUSES)[number];

/** Where an invited supplier stands on one request. */
export type RfqSupplierStatus = (typeof RFQ_SUPPLIER_STATUSES)[number];

/** Where a supplier's quote stands. */
export type RfqQuoteStatus = (typeof RFQ_QUOTE_STATUSES)[number];

/** A request for quotation sent to suppliers. */
export interface Rfq {
  readonly id: string;
  readonly organizationId: string;
  /** `RFQ-1`, or the numbering block's format. */
  readonly number: string;
  readonly title: string;
  readonly status: RfqStatus;
  readonly currency: string;
  /** When quotes are due. */
  readonly dueAt?: Temporal.Instant;
  readonly notes?: string;
  /** The quote an award chose. */
  readonly awardedQuoteId?: string;
  /** The draft purchase order the award created. */
  readonly purchaseOrderId?: string;
  readonly cancelReason?: string;
  readonly openedAt?: Temporal.Instant;
  readonly closedAt?: Temporal.Instant;
  readonly awardedAt?: Temporal.Instant;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

/** One requested item. */
export interface RfqLine {
  readonly id: string;
  readonly rfqId: string;
  /** Position in the request, from 1. */
  readonly ordinal: number;
  readonly description: string;
  /** The inventory variant, needed to turn the award into a purchase order. */
  readonly variantId?: string;
  readonly quantity: number;
  readonly unit?: string;
}

export interface RfqLineInput {
  readonly description: string;
  /** Above zero. */
  readonly quantity: number;
  readonly variantId?: string;
  readonly unit?: string;
}

/** A supplier asked to quote. */
export interface RfqSupplier {
  readonly id: string;
  readonly rfqId: string;
  /** A `config.subjects` type that contacts lists, such as `company`. */
  readonly supplierType: string;
  readonly supplierId: string;
  readonly status: RfqSupplierStatus;
  readonly invitedAt: Temporal.Instant;
  readonly respondedAt?: Temporal.Instant;
}

/** A supplier's price for one requested line. */
export interface RfqQuoteLine {
  readonly id: string;
  readonly quoteId: string;
  readonly lineId: string;
  /** The price of one unit. */
  readonly unitAmount: Money;
  readonly leadTimeDays?: number;
}

/** A supplier's answer to a request. */
export interface RfqQuote {
  readonly id: string;
  readonly rfqId: string;
  readonly invitationId: string;
  readonly status: RfqQuoteStatus;
  /** Unit prices times quantities, over the lines the quote prices. */
  readonly total: Money;
  readonly leadTimeDays?: number;
  readonly validUntil?: Temporal.PlainDate;
  readonly notes?: string;
  /** Goes up each time the supplier quotes again. */
  readonly revision: number;
  readonly submittedBy?: string;
  readonly submittedAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  /** Only on a quote read through `getRfq` or `recordQuote`. */
  readonly lines?: readonly RfqQuoteLine[];
}

/** A request with its lines, suppliers and quotes. */
export interface RfqDetail extends Rfq {
  readonly lines: readonly RfqLine[];
  readonly suppliers: readonly RfqSupplier[];
  readonly quotes: readonly RfqQuote[];
}

export interface RfqInput {
  readonly title: string;
  /** An ISO 4217 code; the quotes are in it. */
  readonly currency: string;
  readonly dueAt?: Temporal.Instant | null;
  readonly notes?: string | null;
}

export interface RfqListOptions {
  readonly status?: RfqStatus;
  /** 1 to 200. Default 50. */
  readonly limit?: number;
  readonly offset?: number;
}

export interface RfqQuoteInput {
  readonly leadTimeDays?: number | null;
  readonly validUntil?: Temporal.PlainDate | null;
  readonly notes?: string | null;
}

/** One price a supplier gives for a requested line. */
export interface RfqQuoteLineInput {
  readonly lineId: string;
  /** The price of one unit, in the request's currency. */
  readonly unitAmount: Money;
  readonly leadTimeDays?: number;
}

/** One supplier's price for a line in a {@link RfqComparison}. */
export interface RfqOffer {
  readonly quoteId: string;
  readonly invitationId: string;
  readonly unitAmount: Money;
  readonly lineTotal: Money;
  readonly leadTimeDays?: number;
  /** Whether it is the best unit price among the live quotes. */
  readonly lowest: boolean;
}

export interface RfqComparisonLine {
  readonly lineId: string;
  readonly ordinal: number;
  readonly description: string;
  readonly quantity: number;
  /** Cheapest first. */
  readonly offers: readonly RfqOffer[];
}

export interface RfqComparisonQuote {
  readonly quoteId: string;
  readonly invitationId: string;
  readonly supplierType: string;
  readonly supplierId: string;
  readonly status: RfqQuoteStatus;
  readonly total: Money;
  readonly leadTimeDays?: number;
  readonly validUntil?: Temporal.PlainDate;
  /** Whether the quote prices every line; only these can win. */
  readonly complete: boolean;
  /** Whether it is the cheapest complete quote. */
  readonly lowest: boolean;
}

/** The live quotes of a request side by side. */
export interface RfqComparison {
  readonly rfqId: string;
  readonly currency: string;
  readonly lines: readonly RfqComparisonLine[];
  /** Cheapest first. */
  readonly quotes: readonly RfqComparisonQuote[];
}

export interface Rfqs {
  /** Creates a draft request with its lines and numbers it; needs `rfqs.write`. */
  createRfq(input: {
    input: RfqInput;
    lines?: readonly RfqLineInput[] | undefined;
  }): AsyncResultType<RfqDetail>;
  /** Changes a draft. Passing `lines` replaces all of them; needs `rfqs.write`. */
  updateRfq(input: {
    rfqId: string;
    input: Partial<RfqInput>;
    lines?: readonly RfqLineInput[] | undefined;
  }): AsyncResultType<RfqDetail>;
  getRfq(rfqId: string): AsyncResultType<RfqDetail>;
  listRfqs(options?: RfqListOptions): AsyncResultType<readonly Rfq[]>;
  /**
   * Asks a supplier to quote. When the contacts block is installed the supplier
   * must be an active supplier there; needs `rfqs.write`.
   */
  inviteSupplier(input: {
    rfqId: string;
    supplier: { readonly type: string; readonly id: string };
  }): AsyncResultType<RfqSupplier>;
  /** Records that a supplier will not quote; needs `rfqs.write`. */
  declineInvitation(invitationId: string): AsyncResultType<RfqSupplier>;
  /** Sends a draft with at least one line and one supplier; needs `rfqs.write`. */
  openRfq(rfqId: string): AsyncResultType<Rfq>;
  /**
   * Records a supplier's prices, or replaces its earlier ones (the revision
   * goes up). Every `lineId` must belong to the request. Only the amounts are
   * sent; they count in the request's currency. The request must be open; needs
   * `rfqs.write`.
   */
  recordQuote(input: {
    rfqId: string;
    invitationId: string;
    lines: readonly RfqQuoteLineInput[];
    input?: RfqQuoteInput | undefined;
  }): AsyncResultType<RfqQuote>;
  /** Withdraws a submitted quote of an open request; needs `rfqs.write`. */
  withdrawQuote(quoteId: string): AsyncResultType<RfqQuote>;
  /** Stops accepting quotes; needs `rfqs.write`. */
  closeRfq(rfqId: string): AsyncResultType<Rfq>;
  /** The live quotes side by side, with the cheapest marked. */
  compare(rfqId: string): AsyncResultType<RfqComparison>;
  /**
   * Awards a request to one quote that prices every line: the others are
   * rejected. With `location` and the inventory block, a draft purchase order
   * for the supplier at the quoted prices is created and its id kept on the
   * request; every line then needs a `variantId`. Needs `rfqs.manage`.
   */
  award(
    input: { rfqId: string; quoteId: string } & { readonly location?: string },
  ): AsyncResultType<Rfq>;
  /**
   * Awards the request to its cheapest quote that prices every line: `compare`
   * then `award`, with the optional `location` for the purchase order. Without
   * such a quote it fails with `RFQ_NO_COMPLETE_QUOTE` and changes nothing.
   * Needs `rfqs.manage`.
   */
  awardBest(input: {
    rfqId: string;
    location?: string | undefined;
  }): AsyncResultType<Rfq>;
  /** Cancels a request that is not awarded; needs `rfqs.manage`. */
  cancelRfq(input: { rfqId: string; reason: string }): AsyncResultType<Rfq>;
}

/** Options for {@link createRfqs}. */
export interface RfqsOptions extends BlockOptions {
  /** `before` and `after` hooks per method (ADR 0015). */
  readonly hooks?: NoInfer<BlockHooks<Rfqs>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

function optional<K extends string, V>(
  key: K,
  value: V | undefined,
): { readonly [P in K]?: V } {
  // SAFETY: a one-key object literal for the key the caller names.
  return (value === undefined ? {} : { [key]: value }) as {
    readonly [P in K]?: V;
  };
}

const definedOf = (input: object): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(input).filter(([, value]) => value !== undefined),
  );

const numberOf = (value: unknown): number | undefined =>
  typeof value === "number" ? value : undefined;

const requiredNumber = (value: unknown, name: string): number => {
  if (typeof value !== "number") {
    throw new TypeError(`${name} is not a number`);
  }

  return value;
};

function plainDate(value: unknown): Temporal.PlainDate | undefined {
  return typeof value === "string"
    ? temporal().PlainDate.from(value)
    : undefined;
}

const amountOf = (value: unknown, currency: string): Money =>
  money(bigintOf(value, "amount"), currency);

function rfqOf(value: unknown, fn: string): Rfq {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    number: textOf(row["number"]),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], RFQ_STATUSES, "rfq status"),
    currency: textOf(row["currency"]),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("dueAt", optionalInstant(row["dueAt"])),
    ...optional("notes", optionalText(row["notes"])),
    ...optional("awardedQuoteId", optionalText(row["awardedQuoteId"])),
    ...optional("purchaseOrderId", optionalText(row["purchaseOrderId"])),
    ...optional("cancelReason", optionalText(row["cancelReason"])),
    ...optional("openedAt", optionalInstant(row["openedAt"])),
    ...optional("closedAt", optionalInstant(row["closedAt"])),
    ...optional("awardedAt", optionalInstant(row["awardedAt"])),
    ...optional("createdBy", optionalText(row["createdBy"])),
  };
}

function lineOf(value: unknown, fn: string): RfqLine {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    rfqId: textOf(row["rfqId"]),
    ordinal: requiredNumber(row["ordinal"], "ordinal"),
    description: textOf(row["description"]),
    quantity: requiredNumber(row["quantity"], "quantity"),
    ...optional("variantId", optionalText(row["variantId"])),
    ...optional("unit", optionalText(row["unit"])),
  };
}

function supplierOf(value: unknown, fn: string): RfqSupplier {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    rfqId: textOf(row["rfqId"]),
    supplierType: textOf(row["supplierType"]),
    supplierId: textOf(row["supplierId"]),
    status: enumOrThrow(
      row["status"],
      RFQ_SUPPLIER_STATUSES,
      "supplier status",
    ),
    invitedAt: requiredInstant(row["invitedAt"], "invitedAt"),
    ...optional("respondedAt", optionalInstant(row["respondedAt"])),
  };
}

function quoteLineOf(
  value: unknown,
  currency: string,
  fn: string,
): RfqQuoteLine {
  const row = recordOf(value, fn);

  return {
    id: textOf(row["id"]),
    quoteId: textOf(row["quoteId"]),
    lineId: textOf(row["lineId"]),
    unitAmount: amountOf(row["unitAmount"], currency),
    ...optional("leadTimeDays", numberOf(row["leadTimeDays"])),
  };
}

function quoteOf(value: unknown, fn: string): RfqQuote {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  const lines = Array.isArray(row["lines"])
    ? recordsOf(row["lines"], fn).map((entry) =>
        quoteLineOf(entry, currency, fn),
      )
    : undefined;

  return {
    id: textOf(row["id"]),
    rfqId: textOf(row["rfqId"]),
    invitationId: textOf(row["invitationId"]),
    status: enumOrThrow(row["status"], RFQ_QUOTE_STATUSES, "quote status"),
    total: amountOf(row["total"], currency),
    revision: requiredNumber(row["revision"], "revision"),
    submittedAt: requiredInstant(row["submittedAt"], "submittedAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    ...optional("leadTimeDays", numberOf(row["leadTimeDays"])),
    ...optional("validUntil", plainDate(row["validUntil"])),
    ...optional("notes", optionalText(row["notes"])),
    ...optional("submittedBy", optionalText(row["submittedBy"])),
    ...optional("lines", lines),
  };
}

function detailOf(value: unknown, fn: string): RfqDetail {
  const row = recordOf(value, fn);
  const rfq = rfqOf(row, fn);

  return {
    ...rfq,
    lines: recordsOf(row["lines"], fn).map((entry) => lineOf(entry, fn)),
    suppliers: recordsOf(row["suppliers"], fn).map((entry) =>
      supplierOf(entry, fn),
    ),
    quotes: recordsOf(row["quotes"], fn).map((entry) => quoteOf(entry, fn)),
  };
}

function comparisonOf(value: unknown, fn: string): RfqComparison {
  const row = recordOf(value, fn);
  const currency = textOf(row["currency"]);

  return {
    rfqId: textOf(row["rfqId"]),
    currency,
    lines: recordsOf(row["lines"], fn).map((entry) => {
      const line = recordOf(entry, fn);

      return {
        lineId: textOf(line["lineId"]),
        ordinal: requiredNumber(line["ordinal"], "ordinal"),
        description: textOf(line["description"]),
        quantity: requiredNumber(line["quantity"], "quantity"),
        offers: recordsOf(line["offers"], fn).map((item) => {
          const offer = recordOf(item, fn);

          return {
            quoteId: textOf(offer["quoteId"]),
            invitationId: textOf(offer["invitationId"]),
            unitAmount: amountOf(offer["unitAmount"], currency),
            lineTotal: amountOf(offer["lineTotal"], currency),
            lowest: offer["lowest"] === true,
            ...optional("leadTimeDays", numberOf(offer["leadTimeDays"])),
          };
        }),
      };
    }),
    quotes: recordsOf(row["quotes"], fn).map((entry) => {
      const quote = recordOf(entry, fn);

      return {
        quoteId: textOf(quote["quoteId"]),
        invitationId: textOf(quote["invitationId"]),
        supplierType: textOf(quote["supplierType"]),
        supplierId: textOf(quote["supplierId"]),
        status: enumOrThrow(quote["status"], RFQ_QUOTE_STATUSES, "status"),
        total: amountOf(quote["total"], currency),
        complete: quote["complete"] === true,
        lowest: quote["lowest"] === true,
        ...optional("leadTimeDays", numberOf(quote["leadTimeDays"])),
        ...optional("validUntil", plainDate(quote["validUntil"])),
      };
    }),
  };
}

function lineArg(line: RfqLineInput): Record<string, unknown> {
  return definedOf(line);
}

/**
 * Requests for quotation: ask several suppliers (parties in contacts) to price
 * the same lines, compare their quotes side by side and award one, which can
 * create the draft purchase order in inventory.
 */
export function createRfqs(options: RfqsOptions): Rfqs {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResultType<string> => requireTenant(options.tenant);

  const client: Rfqs = {
    awardBest: ({ rfqId, location }) =>
      hooked.compare(rfqId).andThen((comparison) => {
        const best = comparison.quotes.find((quote) => quote.complete);

        return best
          ? hooked.award({
              rfqId,
              quoteId: best.quoteId,
              ...(location === undefined ? {} : { location }),
            })
          : AsyncResult.err<Rfq>(
              dbError("not_found", "no quote prices every line", {
                hint: "RFQ_NO_COMPLETE_QUOTE",
              }),
            );
      }),
    createRfq: ({ input, lines = [] }) =>
      tenant().andThen((organizationId) =>
        call(
          "create_rfq",
          {
            tenant: organizationId,
            input: definedOf({ ...input, dueAt: input.dueAt?.toString() }),
            lines: lines.map(lineArg),
          },
          (value) => detailOf(value, "create_rfq"),
        ),
      ),
    updateRfq: ({ rfqId, input, lines }) =>
      call(
        "update_rfq",
        {
          rfq_id: rfqId,
          input: definedOf({
            ...input,
            dueAt: input.dueAt === null ? null : input.dueAt?.toString(),
          }),
          ...(lines === undefined ? {} : { lines: lines.map(lineArg) }),
        },
        (value) => detailOf(value, "update_rfq"),
      ),
    getRfq: (rfqId) =>
      call("get_rfq", { rfq_id: rfqId }, (value) => detailOf(value, "get_rfq")),
    listRfqs: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_rfqs",
          { tenant: organizationId, filters: definedOf(list) },
          (value) =>
            recordsOf(value, "list_rfqs").map((row) => rfqOf(row, "list_rfqs")),
        ),
      ),
    inviteSupplier: ({ rfqId, supplier }) =>
      call(
        "invite_rfq_supplier",
        {
          rfq_id: rfqId,
          supplier_type: supplier.type,
          supplier_id: supplier.id,
        },
        (value) => supplierOf(value, "invite_rfq_supplier"),
      ),
    declineInvitation: (invitationId) =>
      call("decline_rfq_supplier", { invitation_id: invitationId }, (value) =>
        supplierOf(value, "decline_rfq_supplier"),
      ),
    openRfq: (rfqId) =>
      call("open_rfq", { rfq_id: rfqId }, (value) => rfqOf(value, "open_rfq")),
    recordQuote: ({ rfqId, invitationId, lines, input = {} }) =>
      call(
        "record_rfq_quote",
        {
          rfq_id: rfqId,
          invitation_id: invitationId,
          input: definedOf({
            ...input,
            validUntil: input.validUntil?.toString(),
          }),
          lines: lines.map((line) =>
            definedOf({
              lineId: line.lineId,
              unitAmount: line.unitAmount.amount.toString(),
              leadTimeDays: line.leadTimeDays,
            }),
          ),
        },
        (value) => quoteOf(value, "record_rfq_quote"),
      ),
    withdrawQuote: (quoteId) =>
      call("withdraw_rfq_quote", { quote_id: quoteId }, (value) =>
        quoteOf(value, "withdraw_rfq_quote"),
      ),
    closeRfq: (rfqId) =>
      call("close_rfq", { rfq_id: rfqId }, (value) =>
        rfqOf(value, "close_rfq"),
      ),
    compare: (rfqId) =>
      call("compare_rfq", { rfq_id: rfqId }, (value) =>
        comparisonOf(value, "compare_rfq"),
      ),
    award: ({ rfqId, quoteId, ...awardOptions }) =>
      call(
        "award_rfq",
        {
          rfq_id: rfqId,
          quote_id: quoteId,
          ...(awardOptions.location === undefined
            ? {}
            : { location: awardOptions.location }),
        },
        (value) => rfqOf(value, "award_rfq"),
      ),
    cancelRfq: ({ rfqId, reason }) =>
      call("cancel_rfq", { rfq_id: rfqId, reason }, (value) =>
        rfqOf(value, "cancel_rfq"),
      ),
  };

  // Helpers call the hooked client, so app hooks see each step.
  const hooked: Rfqs = withBlockHooks(client, options.hooks, {
    block: "rfqs",
    ...(options.logger ? { logger: options.logger } : {}),
  });

  return hooked;
}
