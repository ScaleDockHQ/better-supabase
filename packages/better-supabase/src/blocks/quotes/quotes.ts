import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  FieldsOf,
  RowFields,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type {
  CatalogLineInput,
  Line,
  LineInput,
  Totals,
} from "../sales-lines.ts";
import type { RecordRef } from "../sales-shared.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import {
  blockFields,
  readFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  amountText,
  amountsError,
  moneyOf,
  unknownCurrency,
} from "../money-codec.ts";
import { lineAmounts, lineArg, lineOf, totalsOf } from "../sales-lines.ts";
import { attrsArg, compact, plainDate, refOf } from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
  bigintOf,
} from "../shared.ts";

export type {
  CatalogLineInput,
  Line,
  LineInput,
  Totals,
} from "../sales-lines.ts";

export type { RecordRef } from "../sales-shared.ts";

export type QuoteStatus =
  | "draft"
  | "sent"
  | "viewed"
  | "accepted"
  | "rejected"
  | "changes_requested"
  | "expired"
  | "withdrawn";

const STATUSES: readonly QuoteStatus[] = [
  "draft",
  "sent",
  "viewed",
  "accepted",
  "rejected",
  "changes_requested",
  "expired",
  "withdrawn",
];

export type QuoteDecision = "accepted" | "rejected" | "changes_requested";

/** A quote line, with its place on the quote. */
export interface QuoteLine extends Line {
  /** 1-based; `selected` in a decision names lines by it. */
  readonly position: number;
  /** The heading the line sits under. */
  readonly section?: string;
  /** An optional line counts only while `selected`. */
  readonly optional: boolean;
  readonly selected: boolean;
}

/** The totals of one tax rate (and tax code), after the document discount. */
export interface QuoteTaxLine {
  readonly taxRateBps: number;
  readonly taxCode?: string;
  readonly net: Money;
  readonly tax: Money;
  readonly gross: Money;
  /** This rate's share of the document discount. */
  readonly discount: Money;
}

/** How a quote is priced: tax-inclusive prices, a document discount, a deposit. */
export interface QuotePricing {
  /** Unit amounts include tax, so tax is counted out of them. */
  readonly pricesIncludeTax: boolean;
  /** A percentage off the whole quote, in basis points (1000 for 10%). */
  readonly discountBps: number;
  /** An amount off the whole quote, after `discountBps`. */
  readonly discountAmount: Money;
  /** The deposit asked on acceptance, in basis points of the total. */
  readonly depositBps?: number;
  /** `depositBps` of the total, in minor units of the quote's currency. */
  readonly depositDue: Money;
}

/** A quote. `F` types the extra columns the `fields` schema describes. */
export interface Quote<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly number: bigint;
  /** `Q-12`; every revision of a quote shares it. */
  readonly identifier: string;
  /** Counts up each time the quote is sent again after a change. */
  readonly revision: number;
  readonly title: string;
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly ownerId?: string;
  readonly currency: string;
  readonly status: QuoteStatus;
  readonly validUntil?: Temporal.PlainDate;
  readonly terms?: string;
  readonly note?: string;
  /** The record it was made from, such as a deal. */
  readonly origin?: RecordRef;
  readonly sentAt?: Temporal.Instant;
  readonly viewedAt?: Temporal.Instant;
  readonly decidedAt?: Temporal.Instant;
  /** Who decided: the customer's name, or the member who recorded it. */
  readonly decidedBy?: string;
  readonly decisionNote?: string;
  /** The signed-in user who decided, a member or a portal guest. */
  readonly decidedUserId?: string;
  /** The customer's IP address and user agent, when they answered. */
  readonly decidedIp?: string;
  readonly decidedUserAgent?: string;
  readonly pricing: QuotePricing;
  readonly lines: readonly QuoteLine[];
  readonly taxLines: readonly QuoteTaxLine[];
  readonly totals: Totals;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
  readonly createdAt: Temporal.Instant;
}

export interface QuoteInput<F extends object = Record<never, never>> {
  readonly title?: string;
  /** Defaults to the lines' currency, then `EUR`. */
  readonly currency?: string;
  readonly company?: RecordRef | null;
  readonly contact?: RecordRef | null;
  readonly ownerId?: string | null;
  readonly validUntil?: Temporal.PlainDate | null;
  readonly terms?: string | null;
  readonly note?: string | null;
  readonly origin?: RecordRef;
  readonly pricesIncludeTax?: boolean;
  readonly discountBps?: number;
  /** In the quote's currency. */
  readonly discountAmount?: Money;
  readonly depositBps?: number | null;
  /**
   * Values for the app's extra columns (`options.extraColumns`); left out keeps
   * the stored ones.
   */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** A published revision: the quote exactly as it was sent then. */
export interface QuoteVersion<F extends object = Record<never, never>> {
  readonly revision: number;
  readonly publishedAt: Temporal.Instant;
  readonly quote: Quote<F>;
}

/** A published revision, without its snapshot. */
export interface QuoteVersionSummary {
  readonly revision: number;
  readonly total: Money;
  readonly publishedAt: Temporal.Instant;
  readonly publishedBy?: string;
}

/** The customer's answer. */
export interface QuoteAnswer {
  readonly name: string;
  readonly note?: string;
  /**
   * On acceptance, the positions of the optional lines the customer takes; the
   * others drop out of the totals. Left out keeps the current choice.
   */
  readonly selected?: readonly number[];
}

/** What a customer's answer did. */
export interface QuoteResponse {
  readonly status: QuoteStatus;
  readonly identifier: string;
  readonly revision: number;
}

/** What the customer sees through the quote's link. */
export interface PublicQuote {
  readonly identifier: string;
  readonly revision: number;
  readonly title: string;
  readonly status: QuoteStatus;
  readonly currency: string;
  readonly validUntil?: Temporal.PlainDate;
  readonly terms?: string;
  readonly pricing: QuotePricing;
  readonly totals: Totals;
  readonly lines: readonly QuoteLine[];
  readonly taxLines: readonly QuoteTaxLine[];
}

/**
 * A quote line. With the catalog block installed, a line can name a product
 * variant and take its price in the quote's currency and its title.
 */
export type QuoteLineInput = (LineInput | CatalogLineInput) & {
  readonly section?: string;
  /** Left out of the totals unless `selected`. */
  readonly optional?: boolean;
  /** Defaults to `true` for a required line and `false` for an optional one. */
  readonly selected?: boolean;
};

export interface Quotes<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: QuoteInput<F> & { readonly title: string },
    lines?: readonly QuoteLineInput[],
  ): AsyncResult<Quote<F>>;
  /** Changes a draft, or a quote with changes requested. */
  update(quoteId: string, input: QuoteInput<F>): AsyncResult<Quote<F>>;
  setLines(
    quoteId: string,
    lines: readonly QuoteLineInput[],
  ): AsyncResult<Totals>;
  /** Sends it: resolves to the quote and the link token, returned only now. */
  send(
    quoteId: string,
  ): AsyncResult<{ readonly quote: Quote<F>; readonly token: string }>;
  /** Records the customer's answer taken another way, with their name. */
  decide(
    quoteId: string,
    decision: QuoteDecision,
    options?: {
      readonly note?: string;
      readonly by?: string;
      readonly selected?: readonly number[];
    },
  ): AsyncResult<Quote<F>>;
  /**
   * Back to draft for changes, as the next revision. The sent revision stays
   * published in `versions`; an accepted quote can't be revised.
   */
  revise(quoteId: string): AsyncResult<Quote<F>>;
  /** The revisions sent so far, oldest first. */
  versions(quoteId: string): AsyncResult<readonly QuoteVersionSummary[]>;
  /** The quote as it was sent at `revision`. */
  version(quoteId: string, revision: number): AsyncResult<QuoteVersion<F>>;
  /** A draft quote from a deal, once per deal. Needs the deals module. */
  fromDeal(dealId: string): AsyncResult<Quote<F>>;
  /** The quote behind a link, for the customer's page. Marks it viewed. */
  view(token: string): AsyncResult<PublicQuote>;
  /** The customer's answer through the link. */
  respond(
    token: string,
    decision: QuoteDecision,
    answer: QuoteAnswer,
  ): AsyncResult<QuoteResponse>;
  /**
   * A quote shared with the signed-in guest (portal), as the customer sees it.
   * Marks it viewed.
   */
  portalView(quoteId: string): AsyncResult<PublicQuote>;
  /**
   * The signed-in guest's answer, with no token. The name defaults to the
   * guest's email.
   */
  portalRespond(
    quoteId: string,
    decision: QuoteDecision,
    answer?: Partial<QuoteAnswer>,
  ): AsyncResult<QuoteResponse>;
  /** Expires sent quotes past their date. Service role only. */
  expire(): AsyncResult<number>;
}

export interface QuotesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  /**
   * A Standard Schema for the extra columns of the quotes table
   * (`blocks.quotes.options.extraColumns`): writes are validated, reads
   * parsed.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Quotes<FieldsOf<S>>>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const KNOWN = new Set([
  "id",
  "tenant_id",
  "number",
  "identifier",
  "revision",
  "title",
  "company_type",
  "company_id",
  "contact_type",
  "contact_id",
  "owner_user_id",
  "currency",
  "status",
  "valid_until",
  "terms",
  "note",
  "origin_type",
  "origin_id",
  "sent_at",
  "viewed_at",
  "decided_at",
  "decided_by",
  "decision_note",
  "decided_user_id",
  "decided_ip",
  "decided_user_agent",
  "prices_include_tax",
  "discount_bps",
  "discount_amount",
  "deposit_bps",
  "deposit_due",
  "created_by",
  "created_at",
  "updated_at",
  "list_total",
  "discount_total",
  "subtotal",
  "tax_total",
  "total",
  "lines",
  "tax_lines",
  "taxLines",
  "token",
  "fields",
  "publishedAt",
]);

function quoteLineOf(value: unknown, currency: string): QuoteLine {
  const row = recordOf(value, "quote line");
  const optional = row["optional"] === true;

  return compact<QuoteLine>({
    ...lineOf(row, currency),
    position: Number(row["position"] ?? 0),
    section: optionalText(row["section"]),
    optional,
    selected:
      typeof row["selected"] === "boolean" ? row["selected"] : !optional,
  });
}

function taxLineOf(value: unknown, currency: string): QuoteTaxLine {
  const row = recordOf(value, "quote tax line");

  const at = (key: string): Money =>
    moneyOf(row[key] ?? "0", currency, `quote tax line ${key}`);

  return compact<QuoteTaxLine>({
    taxRateBps: Number(row["taxRateBps"] ?? 0),
    taxCode: optionalText(row["taxCode"]),
    net: at("net"),
    tax: at("tax"),
    gross: at("gross"),
    discount: at("discount"),
  });
}

/** Pricing from a row (snake keys) or a public quote (camel keys). */
function pricingOf(
  row: Readonly<Record<string, unknown>>,
  currency: string,
  camel: boolean,
): QuotePricing {
  const key = (snake: string, camelKey: string): unknown =>
    camel ? row[camelKey] : row[snake];

  const depositBps = key("deposit_bps", "depositBps");

  return compact<QuotePricing>({
    pricesIncludeTax: key("prices_include_tax", "pricesIncludeTax") === true,
    discountBps: Number(key("discount_bps", "discountBps") ?? 0),
    discountAmount: moneyOf(
      key("discount_amount", "discountAmount") ?? "0",
      currency,
      "quote discountAmount",
    ),
    depositBps:
      depositBps === null || depositBps === undefined
        ? undefined
        : Number(depositBps),
    depositDue: moneyOf(
      key("deposit_due", "depositDue") ?? "0",
      currency,
      "quote depositDue",
    ),
  });
}

function responseOf(value: unknown): QuoteResponse {
  const row = recordOf(value, "quote response");

  return {
    status: enumOrThrow(row["status"], STATUSES, "quote status"),
    identifier: textOf(row["identifier"]),
    revision: Number(row["revision"] ?? 1),
  };
}

function versionSummaryOf(value: unknown): QuoteVersionSummary {
  const row = recordOf(value, "quote version");

  return compact<QuoteVersionSummary>({
    revision: Number(row["revision"]),
    total: moneyOf(row["total"], row["currency"], "quote version total"),
    publishedAt: requiredInstant(row["publishedAt"], "publishedAt"),
    publishedBy: optionalText(row["publishedBy"]),
  });
}

function quoteOf(value: unknown): Quote {
  const row = recordOf(value, "quote");
  const currency = textOf(row["currency"]);

  return compact<Quote>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    number: bigintOf(row["number"], "quote number"),
    identifier: textOf(row["identifier"]),
    revision: Number(row["revision"] ?? 1),
    title: textOf(row["title"]),
    company: refOf(row["company_type"], row["company_id"]),
    contact: refOf(row["contact_type"], row["contact_id"]),
    ownerId: optionalText(row["owner_user_id"]),
    currency,
    status: enumOrThrow(row["status"], STATUSES, "quote status"),
    validUntil: plainDate(row["valid_until"]),
    terms: optionalText(row["terms"]),
    note: optionalText(row["note"]),
    origin: refOf(row["origin_type"], row["origin_id"]),
    sentAt: optionalInstant(row["sent_at"]),
    viewedAt: optionalInstant(row["viewed_at"]),
    decidedAt: optionalInstant(row["decided_at"]),
    decidedBy: optionalText(row["decided_by"]),
    decisionNote: optionalText(row["decision_note"]),
    decidedUserId: optionalText(row["decided_user_id"]),
    decidedIp: optionalText(row["decided_ip"]),
    decidedUserAgent: optionalText(row["decided_user_agent"]),
    pricing: pricingOf(row, currency, false),
    lines: recordsOf(row["lines"], "quote lines").map((line) =>
      quoteLineOf(line, currency),
    ),
    taxLines: recordsOf(row["taxLines"] ?? [], "quote tax lines").map((line) =>
      taxLineOf(line, currency),
    ),
    totals: totalsOf(row, false),
    // Rows from the module carry `fields`; an adopted table's rows carry
    // the app's columns next to the module's.
    fields: isRecord(row["fields"])
      ? row["fields"]
      : Object.fromEntries(
          Object.entries(row).filter(([key]) => !KNOWN.has(key)),
        ),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
  });
}

function publicOf(value: unknown): PublicQuote {
  const row = recordOf(value, "public_quote");
  const currency = textOf(row["currency"]);

  return compact<PublicQuote>({
    identifier: textOf(row["identifier"]),
    revision: Number(row["revision"] ?? 1),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], STATUSES, "quote status"),
    currency,
    validUntil: plainDate(row["validUntil"]),
    terms: optionalText(row["terms"]),
    pricing: pricingOf(row, currency, true),
    totals: totalsOf(
      { ...row, listTotal: row["listTotal"] ?? row["subtotal"] },
      true,
    ),
    lines: recordsOf(row["lines"], "quote lines").map((line) =>
      quoteLineOf(line, currency),
    ),
    taxLines: recordsOf(row["taxLines"] ?? [], "quote tax lines").map((line) =>
      taxLineOf(line, currency),
    ),
  });
}

/**
 * The quotes block: quotes with lines, sections and optional lines, document
 * discounts and tax-inclusive prices, published versions, a public link and a
 * portal the customer answers through, expiry, and quotes made from deals.
 */
export function createQuotes<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: QuotesOptions<S>): Quotes<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "quote fields");

  const quote = <T extends { readonly fields: object }>(
    fn: string,
    args: Readonly<Record<string, unknown>>,
    then: (value: unknown) => T,
  ) => call(fn, args, then).andThen((row) => readFields(fields, row));

  const attrsOf = (
    input: QuoteInput<F>,
    checked: Readonly<Record<string, unknown>> | undefined,
  ): Record<string, unknown> => {
    const { fields: _fields, discountAmount, ...rest } = input;

    return {
      ...attrsArg(rest),
      ...(discountAmount === undefined
        ? {}
        : { discountAmount: amountText(discountAmount) }),
      ...(checked === undefined ? {} : { fields: checked }),
    };
  };

  const client: Quotes<F> = {
    create: (organizationId, input, lines) => {
      const amounts = lineAmounts(lines ?? []);
      const invalid = amountsError(input.currency, amounts);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      const currency = input.currency ?? amounts[0]?.currency;

      const withCurrency =
        currency === undefined ? input : { ...input, currency };

      return writeFields(fields, input.fields, (checked) =>
        quote(
          "create_quote",
          {
            tenant: organizationId,
            attrs: attrsOf(withCurrency, checked),
            lines: lines === undefined ? null : lines.map(lineArg),
          },
          quoteOf,
        ),
      );
    },
    update: (quoteId, input) =>
      input.currency !== undefined &&
      amountsError(input.currency, []) !== undefined
        ? AsyncResult.err(unknownCurrency(input.currency))
        : writeFields(fields, input.fields, (checked) =>
            quote(
              "update_quote",
              { quote: quoteId, attrs: attrsOf(input, checked) },
              quoteOf,
            ),
          ),
    setLines: (quoteId, lines) => {
      const invalid = amountsError(undefined, lineAmounts(lines));

      return invalid === undefined
        ? call(
            "set_quote_lines",
            { parent: quoteId, lines: lines.map(lineArg) },
            (value) => totalsOf(recordOf(value, "set_quote_lines"), true),
          )
        : AsyncResult.err(invalid);
    },
    send: (quoteId) =>
      call("send_quote", { quote: quoteId }, (value) => ({
        quote: quoteOf(value),
        token: textOf(recordOf(value, "send_quote")["token"]),
      })).andThen((sent) =>
        readFields(fields, sent.quote).map((parsed) => ({
          quote: parsed,
          token: sent.token,
        })),
      ),
    decide: (quoteId, decision, decide = {}) =>
      quote(
        "decide_quote",
        {
          quote: quoteId,
          decision,
          note: decide.note ?? null,
          by: decide.by ?? null,
          selected: decide.selected ?? null,
        },
        quoteOf,
      ),
    revise: (quoteId) => quote("revise_quote", { quote: quoteId }, quoteOf),
    versions: (quoteId) =>
      call("quote_versions", { quote: quoteId }, (value) =>
        recordsOf(value, "quote versions").map(versionSummaryOf),
      ),
    version: (quoteId, revision) =>
      call("quote_version", { quote: quoteId, revision }, (value) => {
        const row = recordOf(value, "quote version");

        return {
          revision: Number(row["revision"]),
          publishedAt: requiredInstant(row["publishedAt"], "publishedAt"),
          quote: quoteOf(row),
        };
      }).andThen((version) =>
        readFields(fields, version.quote).map((parsed) => ({
          ...version,
          quote: parsed,
        })),
      ),
    fromDeal: (dealId) => quote("quote_from_deal", { deal: dealId }, quoteOf),
    view: (token) => call("public_quote", { token }, publicOf),
    respond: (token, decision, answer) =>
      call(
        "respond_to_quote",
        {
          token,
          decision,
          name: answer.name,
          note: answer.note ?? null,
          selected: answer.selected ?? null,
        },
        responseOf,
      ),
    portalView: (quoteId) => call("portal_quote", { quote: quoteId }, publicOf),
    portalRespond: (quoteId, decision, answer = {}) =>
      call(
        "respond_to_portal_quote",
        {
          quote: quoteId,
          decision,
          name: answer.name ?? null,
          note: answer.note ?? null,
          selected: answer.selected ?? null,
        },
        responseOf,
      ),
    expire: () => call("expire_quotes", {}, (value) => Number(value ?? 0)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "quotes",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
