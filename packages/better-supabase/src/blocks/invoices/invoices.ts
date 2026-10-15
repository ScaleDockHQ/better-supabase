import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { AsyncResult } from "../../core/result.ts";

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
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type { Line, LineInput, RecordRef, Totals } from "../sales-shared.ts";

export type InvoiceStatus =
  | "draft"
  | "issued"
  | "partially_paid"
  | "paid"
  | "void"
  | "uncollectible";

const STATUSES: readonly InvoiceStatus[] = [
  "draft",
  "issued",
  "partially_paid",
  "paid",
  "void",
  "uncollectible",
];

export interface InvoicePayment {
  readonly id: string;
  /** Minor units; negative for a refund. */
  readonly amount: bigint;
  readonly paidAt: Temporal.Instant;
  readonly method?: string;
  readonly reference?: string;
}

export interface Invoice {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: "invoice" | "credit_note";
  /** Set on issue; a draft has none. */
  readonly number?: bigint;
  readonly identifier?: string;
  /** The invoice a credit note credits. */
  readonly originalId?: string;
  readonly title: string;
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly currency: string;
  readonly status: InvoiceStatus;
  readonly termsDays: number;
  readonly issuedOn?: Temporal.PlainDate;
  readonly dueOn?: Temporal.PlainDate;
  /** Open and past its due date. */
  readonly overdue: boolean;
  readonly paidTotal: bigint;
  readonly creditedTotal: bigint;
  /** Total minus credits minus payments. */
  readonly balance: bigint;
  readonly paidAt?: Temporal.Instant;
  readonly voidReason?: string;
  readonly note?: string;
  readonly origin?: RecordRef;
  /** For a deposit invoice: its share of the quote in basis points. */
  readonly depositBps?: number;
  readonly lines: readonly Line[];
  readonly payments: readonly InvoicePayment[];
  readonly totals: Totals;
  readonly fields: Readonly<Record<string, unknown>>;
  readonly createdAt: Temporal.Instant;
}

export interface InvoiceInput {
  readonly title: string;
  readonly currency?: string;
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly termsDays?: number;
  readonly note?: string;
  readonly origin?: RecordRef;
}

/** What is owed in one currency, by days past due. Minor units. */
export interface InvoiceAging {
  readonly currency: string;
  readonly current: bigint;
  readonly days1To30: bigint;
  readonly days31To60: bigint;
  readonly days61To90: bigint;
  readonly over90: bigint;
  readonly outstanding: bigint;
  readonly overdueCount: number;
}

export interface Invoices {
  create(
    organizationId: string,
    input: InvoiceInput,
    lines?: readonly LineInput[],
  ): AsyncResult<Invoice>;
  setLines(invoiceId: string, lines: readonly LineInput[]): AsyncResult<Totals>;
  /** Issues a draft: the next number, issue and due dates, frozen lines. */
  issue(invoiceId: string, issuedOn?: Temporal.PlainDate): AsyncResult<Invoice>;
  /** Records a payment; a negative amount is a refund. */
  recordPayment(
    invoiceId: string,
    payment: {
      readonly amount: bigint;
      readonly paidAt?: Temporal.Instant;
      readonly method?: string;
      /** Unique per organization, so a replayed payment is added once. */
      readonly reference?: string;
    },
  ): AsyncResult<Invoice>;
  /** A draft credit note for the whole invoice, or for the given lines. */
  credit(
    invoiceId: string,
    options?: { readonly lines?: readonly LineInput[]; readonly note?: string },
  ): AsyncResult<Invoice>;
  void(invoiceId: string, reason?: string): AsyncResult<Invoice>;
  writeOff(invoiceId: string): AsyncResult<Invoice>;
  aging(
    organizationId: string,
    currency: string,
    asOf?: Temporal.PlainDate,
  ): AsyncResult<InvoiceAging>;
  /**
   * An invoice from an accepted quote: the full invoice once, minus the
   * deposits already issued, or a deposit invoice for `depositBps` of it.
   */
  fromQuote(
    quoteId: string,
    options?: { readonly depositBps?: number },
  ): AsyncResult<Invoice>;
}

export interface InvoicesOptions extends BlockTemporalOptions {
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Invoices>>;
  readonly logger?: Logger;
  readonly mappers?: readonly ErrorMapper[];
}

const KNOWN = new Set([
  "id",
  "tenant_id",
  "kind",
  "number",
  "identifier",
  "original_id",
  "title",
  "company_type",
  "company_id",
  "contact_type",
  "contact_id",
  "currency",
  "status",
  "terms_days",
  "issued_on",
  "due_on",
  "paid_total",
  "credited_total",
  "paid_at",
  "voided_at",
  "void_reason",
  "note",
  "origin_type",
  "origin_id",
  "deposit_bps",
  "created_by",
  "created_at",
  "updated_at",
  "list_total",
  "discount_total",
  "subtotal",
  "tax_total",
  "total",
  "lines",
  "payments",
  "balance",
  "overdue",
]);

function invoiceOf(value: unknown): Invoice {
  const row = recordOf(value, "invoice");
  return compact<Invoice>({
    id: textOf(row["id"]),
    organizationId: textOf(row["tenant_id"]),
    kind: enumOrThrow(
      row["kind"],
      ["invoice", "credit_note"] as const,
      "invoice kind",
    ),
    number:
      row["number"] === null || row["number"] === undefined
        ? undefined
        : big(row["number"]),
    identifier: optionalText(row["identifier"]),
    originalId: optionalText(row["original_id"]),
    title: textOf(row["title"]),
    company: refOf(row["company_type"], row["company_id"]),
    contact: refOf(row["contact_type"], row["contact_id"]),
    currency: textOf(row["currency"]),
    status: enumOrThrow(row["status"], STATUSES, "invoice status"),
    termsDays: Number(row["terms_days"] ?? 0),
    issuedOn: plainDate(row["issued_on"]),
    dueOn: plainDate(row["due_on"]),
    overdue: row["overdue"] === true,
    paidTotal: big(row["paid_total"]),
    creditedTotal: big(row["credited_total"]),
    balance: big(row["balance"]),
    paidAt: optionalInstant(row["paid_at"]),
    voidReason: optionalText(row["void_reason"]),
    note: optionalText(row["note"]),
    origin: refOf(row["origin_type"], row["origin_id"]),
    depositBps:
      typeof row["deposit_bps"] === "number" ? row["deposit_bps"] : undefined,
    lines: recordsOf(row["lines"], "invoice lines").map(lineOf),
    payments: recordsOf(row["payments"], "invoice payments").map((payment) =>
      compact<InvoicePayment>({
        id: textOf(payment["id"]),
        amount: big(payment["amount"]),
        paidAt: requiredInstant(payment["paidAt"], "paidAt"),
        method: optionalText(payment["method"]),
        reference: optionalText(payment["reference"]),
      }),
    ),
    totals: totalsOf(row, false),
    fields: Object.fromEntries(
      Object.entries(row).filter(([key]) => !KNOWN.has(key)),
    ),
    createdAt: requiredInstant(row["created_at"], "createdAt"),
  });
}

/**
 * The invoices block: invoices an organization sends its own customers,
 * numbered on issue, with payments, credit notes, void, write-off, aging,
 * and invoices from accepted quotes.
 */
export function createInvoices(options: InvoicesOptions): Invoices {
  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const client: Invoices = {
    create: (organizationId, input, lines) =>
      call(
        "create_invoice",
        {
          tenant: organizationId,
          attrs: attrsArg(input),
          lines: lines === undefined ? null : lines.map(lineArg),
        },
        invoiceOf,
      ),
    setLines: (invoiceId, lines) =>
      call(
        "set_invoice_lines",
        { parent: invoiceId, lines: lines.map(lineArg) },
        (value) => totalsOf(recordOf(value, "set_invoice_lines"), true),
      ),
    issue: (invoiceId, issuedOn) =>
      call(
        "issue_invoice",
        {
          invoice: invoiceId,
          issued_on: issuedOn === undefined ? null : issuedOn.toString(),
        },
        invoiceOf,
      ),
    recordPayment: (invoiceId, payment) =>
      call(
        "record_invoice_payment",
        {
          invoice: invoiceId,
          amount: payment.amount.toString(),
          paid_at: instantArg(payment.paidAt) ?? null,
          method: payment.method ?? null,
          reference: payment.reference ?? null,
        },
        invoiceOf,
      ),
    credit: (invoiceId, credit = {}) =>
      call(
        "credit_invoice",
        {
          invoice: invoiceId,
          lines: credit.lines === undefined ? null : credit.lines.map(lineArg),
          note: credit.note ?? null,
        },
        invoiceOf,
      ),
    void: (invoiceId, reason) =>
      call(
        "void_invoice",
        { invoice: invoiceId, reason: reason ?? null },
        invoiceOf,
      ),
    writeOff: (invoiceId) =>
      call("write_off_invoice", { invoice: invoiceId }, invoiceOf),
    aging: (organizationId, currency, asOf) =>
      call(
        "invoice_aging",
        {
          tenant: organizationId,
          currency,
          as_of: asOf === undefined ? null : asOf.toString(),
        },
        (value) => {
          const row = recordOf(value, "invoice_aging");
          return {
            currency: textOf(row["currency"]),
            current: big(row["current"]),
            days1To30: big(row["days1To30"]),
            days31To60: big(row["days31To60"]),
            days61To90: big(row["days61To90"]),
            over90: big(row["over90"]),
            outstanding: big(row["outstanding"]),
            overdueCount: Number(row["overdueCount"] ?? 0),
          };
        },
      ),
    fromQuote: (quoteId, fromQuote = {}) =>
      call(
        "invoice_from_quote",
        { quote: quoteId, deposit_bps: fromQuote.depositBps ?? null },
        invoiceOf,
      ),
  };
  return withBlockHooks(client, options.hooks, {
    block: "invoices",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
