import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";

import {
  type BlockFields,
  blockFields,
  type FieldsOf,
  readFields,
  type RowFields,
  writeFields,
} from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import {
  attrsArg,
  big,
  compact,
  type Line,
  type LineInput,
  lineArg,
  lineOf,
  plainDate,
  type RecordRef,
  refOf,
  type Totals,
  totalsOf,
} from "../sales-shared.ts";
import {
  applyTemporal,
  blockCall,
  type BlockTemporalOptions,
  enumOrThrow,
  isRecord,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type { Line, LineInput, RecordRef, Totals } from "../sales-shared.ts";

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

/** A quote. `F` types the extra columns the `fields` schema describes. */
export interface Quote<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly number: bigint;
  /** `Q-12`; every revision of a quote shares it. */
  readonly identifier: string;
  readonly revision: number;
  /** The revision this one replaces. */
  readonly supersedesId?: string;
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
  readonly lines: readonly Line[];
  readonly totals: Totals;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: RowFields<F>;
  readonly createdAt: Temporal.Instant;
}

export interface QuoteInput<F extends object = Record<never, never>> {
  readonly title?: string;
  readonly currency?: string;
  readonly company?: RecordRef | null;
  readonly contact?: RecordRef | null;
  readonly ownerId?: string | null;
  readonly validUntil?: Temporal.PlainDate | null;
  readonly terms?: string | null;
  readonly note?: string | null;
  readonly origin?: RecordRef;
  /** Values for the app's extra columns (`options.extraColumns`); left out keeps the stored ones. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
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
  readonly subtotal: bigint;
  readonly discountTotal: bigint;
  readonly taxTotal: bigint;
  readonly total: bigint;
  readonly lines: readonly Line[];
}

export interface Quotes<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: QuoteInput<F> & { readonly title: string },
    lines?: readonly LineInput[],
  ): AsyncResult<Quote<F>>;
  /** Changes a draft, or a quote with changes requested. */
  update(quoteId: string, input: QuoteInput<F>): AsyncResult<Quote<F>>;
  setLines(quoteId: string, lines: readonly LineInput[]): AsyncResult<Totals>;
  /** Sends it: resolves to the quote and the link token, returned only now. */
  send(
    quoteId: string,
  ): AsyncResult<{ readonly quote: Quote<F>; readonly token: string }>;
  /** Records the customer's answer taken another way, with their name. */
  decide(
    quoteId: string,
    decision: QuoteDecision,
    options?: { readonly note?: string; readonly by?: string },
  ): AsyncResult<Quote<F>>;
  /** A new draft revision; the old one is withdrawn unless accepted. */
  revise(quoteId: string): AsyncResult<Quote<F>>;
  /** A draft quote from a deal, once per deal. Needs the deals module. */
  fromDeal(dealId: string): AsyncResult<Quote<F>>;
  /** The quote behind a link, for the customer's page. Marks it viewed. */
  view(token: string): AsyncResult<PublicQuote>;
  /** The customer's answer through the link. */
  respond(
    token: string,
    decision: QuoteDecision,
    answer: { readonly name: string; readonly note?: string },
  ): AsyncResult<{ readonly status: QuoteStatus }>;
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
  "supersedes_id",
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
  "created_by",
  "created_at",
  "updated_at",
  "list_total",
  "discount_total",
  "subtotal",
  "tax_total",
  "total",
  "lines",
  "token",
  "fields",
]);

function quoteOf(value: unknown): Quote {
  const row = recordOf(value, "quote");

  return compact<Quote>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    number: big(row["number"]),
    identifier: textOf(row["identifier"]),
    revision: Number(row["revision"] ?? 1),
    supersedesId: optionalText(row["supersedes_id"]),
    title: textOf(row["title"]),
    company: refOf(row["company_type"], row["company_id"]),
    contact: refOf(row["contact_type"], row["contact_id"]),
    ownerId: optionalText(row["owner_user_id"]),
    currency: textOf(row["currency"]),
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
    lines: recordsOf(row["lines"], "quote lines").map(lineOf),
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

  return compact<PublicQuote>({
    identifier: textOf(row["identifier"]),
    revision: Number(row["revision"] ?? 1),
    title: textOf(row["title"]),
    status: enumOrThrow(row["status"], STATUSES, "quote status"),
    currency: textOf(row["currency"]),
    validUntil: plainDate(row["validUntil"]),
    terms: optionalText(row["terms"]),
    subtotal: big(row["subtotal"]),
    discountTotal: big(row["discountTotal"]),
    taxTotal: big(row["taxTotal"]),
    total: big(row["total"]),
    lines: recordsOf(row["lines"], "quote lines").map(lineOf),
  });
}

/**
 * The quotes block: quotes with lines, a revision chain, a public link the
 * customer answers through, expiry, and quotes made from deals.
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
    const { fields: _fields, ...rest } = input;

    return {
      ...attrsArg(rest),
      ...(checked === undefined ? {} : { fields: checked }),
    };
  };

  const client: Quotes<F> = {
    create: (organizationId, input, lines) =>
      writeFields(fields, input.fields, (checked) =>
        quote(
          "create_quote",
          {
            tenant: organizationId,
            attrs: attrsOf(input, checked),
            lines: lines === undefined ? null : lines.map(lineArg),
          },
          quoteOf,
        ),
      ),
    update: (quoteId, input) =>
      writeFields(fields, input.fields, (checked) =>
        quote(
          "update_quote",
          { quote: quoteId, attrs: attrsOf(input, checked) },
          quoteOf,
        ),
      ),
    setLines: (quoteId, lines) =>
      call(
        "set_quote_lines",
        { parent: quoteId, lines: lines.map(lineArg) },
        (value) => totalsOf(recordOf(value, "set_quote_lines"), true),
      ),
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
        },
        quoteOf,
      ),
    revise: (quoteId) => quote("revise_quote", { quote: quoteId }, quoteOf),
    fromDeal: (dealId) => quote("quote_from_deal", { deal: dealId }, quoteOf),
    view: (token) => call("public_quote", { token }, publicOf),
    respond: (token, decision, answer) =>
      call(
        "respond_to_quote",
        { token, decision, name: answer.name, note: answer.note ?? null },
        (value) => ({
          status: enumOrThrow(
            recordOf(value, "respond_to_quote")["status"],
            STATUSES,
            "quote status",
          ),
        }),
      ),
    expire: () => call("expire_quotes", {}, (value) => Number(value ?? 0)),
  };

  return withBlockHooks(client, options.hooks, {
    block: "quotes",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
