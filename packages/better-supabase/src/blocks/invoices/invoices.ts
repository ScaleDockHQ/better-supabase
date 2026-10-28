import type { Money } from "../../commerce/money.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { Line, LineInput, Totals } from "../sales-lines.ts";
import type { RecordRef } from "../sales-shared.ts";
import type { BlockTemporalOptions } from "../shared.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { isRecord } from "../../core/guards.ts";
import { AsyncResult } from "../../core/result.ts";
import {
  amountsError,
  amountText,
  moneyOf,
  unknownCurrency,
} from "../money-codec.ts";
import { lineArg, lineOf, totalsOf } from "../sales-lines.ts";
import { attrsArg, compact, plainDate, refOf } from "../sales-shared.ts";
import {
  bigintOf,
  applyTemporal,
  blockCall,
  enumOrThrow,
  instantArg,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  requiredInstant,
  textOf,
} from "../shared.ts";

export type { Line, LineInput, Totals } from "../sales-lines.ts";

export type { RecordRef } from "../sales-shared.ts";

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
  /** In the invoice's currency; negative for a refund. */
  readonly amount: Money;
  readonly paidAt: Temporal.Instant;
  readonly method?: string;
  readonly reference?: string;
}

/** An amount added on top of an issued invoice, such as collection costs. */
export interface InvoiceCharge {
  readonly id: string;
  readonly amount: Money;
  readonly description?: string;
  readonly createdAt?: Temporal.Instant;
  /** The charge's extra columns (`options.chargeExtraColumns`). */
  readonly fields?: Readonly<Record<string, unknown>>;
}

/** An invoice. `F` types the extra columns the `fields` schema describes. */
export interface Invoice<F extends object = Record<never, never>> {
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
  readonly paidTotal: Money;
  readonly creditedTotal: Money;
  /** Total plus charges minus credits minus payments. */
  readonly balance: Money;
  /** The sum of the charges added on top of the total. */
  readonly chargedTotal?: Money;
  readonly charges?: readonly InvoiceCharge[];
  readonly paidAt?: Temporal.Instant;
  readonly voidReason?: string;
  readonly note?: string;
  readonly origin?: RecordRef;
  /** For a deposit invoice: its share of the quote in basis points. */
  readonly depositBps?: number;
  readonly lines: readonly Line[];
  readonly payments: readonly InvoicePayment[];
  readonly totals: Totals;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
  readonly createdAt: Temporal.Instant;
}

export interface InvoiceInput<F extends object = Record<never, never>> {
  readonly title: string;
  /** Defaults to the lines' currency, then `EUR`. */
  readonly currency?: string;
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly termsDays?: number;
  readonly note?: string;
  readonly origin?: RecordRef;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

/** What is owed in one currency, by days past due. */
export interface InvoiceAging {
  readonly currency: string;
  readonly current: Money;
  readonly days1To30: Money;
  readonly days31To60: Money;
  readonly days61To90: Money;
  readonly over90: Money;
  readonly outstanding: Money;
  readonly overdueCount: number;
}

/** `F` types the invoices' extra columns, from the `fields` schema. */
export interface Invoices<F extends object = Record<never, never>> {
  create(
    organizationId: string,
    input: InvoiceInput<F>,
    lines?: readonly LineInput[],
  ): AsyncResult<Invoice<F>>;
  setLines(invoiceId: string, lines: readonly LineInput[]): AsyncResult<Totals>;
  /** Issues a draft: the next number, issue and due dates, frozen lines. */
  issue(
    invoiceId: string,
    issuedOn?: Temporal.PlainDate,
  ): AsyncResult<Invoice<F>>;
  /** Records a payment; a negative amount is a refund. */
  recordPayment(
    invoiceId: string,
    payment: {
      /** In the invoice's currency. */
      readonly amount: Money;
      readonly paidAt?: Temporal.Instant;
      readonly method?: string;
      /** Unique per organization, so a replayed payment is added once. */
      readonly reference?: string;
    },
  ): AsyncResult<Invoice<F>>;
  /** A draft credit note for the whole invoice, or for the given lines. */
  credit(
    invoiceId: string,
    options?: { readonly lines?: readonly LineInput[]; readonly note?: string },
  ): AsyncResult<Invoice<F>>;
  void(invoiceId: string, reason?: string): AsyncResult<Invoice<F>>;
  writeOff(invoiceId: string): AsyncResult<Invoice<F>>;
  /**
   * Adds a charge on top of an issued invoice's total, in its currency. The
   * balance rises, so a paid invoice is open again until the charge is paid.
   */
  charge(
    invoiceId: string,
    charge: {
      readonly amount: Money;
      readonly description?: string;
      /** The charge's extra columns (`options.chargeExtraColumns`) by name. */
      readonly fields?: Readonly<Record<string, unknown>>;
    },
  ): AsyncResult<Invoice<F>>;
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
  ): AsyncResult<Invoice<F>>;
}

export interface InvoicesOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockTemporalOptions {
  /**
   * A Standard Schema for the invoices' extra columns
   * (`blocks.invoices.options.extraColumns`), keyed by column name. It types
   * and parses `fields` on reads and validates them on `create`.
   */
  readonly fields?: S;
  readonly transport: BlockTransport;
  readonly schema?: string;
  readonly hooks?: NoInfer<BlockHooks<Invoices<FieldsOf<S>>>>;
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
  "charges",
  "charged_total",
]);

function invoiceOf(value: unknown): Invoice {
  const row = recordOf(value, "invoice");
  const currency = textOf(row["currency"]);

  const at = (key: string, field: string): Money =>
    moneyOf(row[key], currency, `invoice ${field}`);

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
        : bigintOf(row["number"], "invoice number"),
    identifier: optionalText(row["identifier"]),
    originalId: optionalText(row["original_id"]),
    title: textOf(row["title"]),
    company: refOf(row["company_type"], row["company_id"]),
    contact: refOf(row["contact_type"], row["contact_id"]),
    currency,
    status: enumOrThrow(row["status"], STATUSES, "invoice status"),
    termsDays: Number(row["terms_days"] ?? 0),
    issuedOn: plainDate(row["issued_on"]),
    dueOn: plainDate(row["due_on"]),
    overdue: row["overdue"] === true,
    paidTotal: at("paid_total", "paidTotal"),
    creditedTotal: at("credited_total", "creditedTotal"),
    balance: at("balance", "balance"),
    chargedTotal:
      row["charged_total"] === undefined
        ? undefined
        : at("charged_total", "chargedTotal"),
    charges:
      row["charges"] === undefined
        ? undefined
        : recordsOf(row["charges"], "invoice charges").map((charge) =>
            compact<InvoiceCharge>({
              id: textOf(charge["id"]),
              amount: moneyOf(
                charge["amount"],
                currency,
                "invoice charge amount",
              ),
              description: optionalText(charge["description"]),
              createdAt: optionalInstant(charge["createdAt"]),
              fields: isRecord(charge["fields"]) ? charge["fields"] : undefined,
            }),
          ),
    paidAt: optionalInstant(row["paid_at"]),
    voidReason: optionalText(row["void_reason"]),
    note: optionalText(row["note"]),
    origin: refOf(row["origin_type"], row["origin_id"]),
    depositBps:
      typeof row["deposit_bps"] === "number" ? row["deposit_bps"] : undefined,
    lines: recordsOf(row["lines"], "invoice lines").map((line) =>
      lineOf(line, currency),
    ),
    payments: recordsOf(row["payments"], "invoice payments").map((payment) =>
      compact<InvoicePayment>({
        id: textOf(payment["id"]),
        amount: moneyOf(payment["amount"], currency, "invoice payment amount"),
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
 * numbered on issue, with payments, credit notes, void, write-off, aging, and
 * invoices from accepted quotes.
 */
export function createInvoices<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: InvoicesOptions<S>): Invoices<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const fields: BlockFields<F> = blockFields(options.fields, "invoice fields");

  const invoice = (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ): AsyncResult<Invoice<F>> =>
    call(fn, args, invoiceOf).andThen((read) =>
      AsyncResult.from(() => fields.read(read.fields)).map((value) => ({
        ...read,
        fields: value,
      })),
    );

  const client: Invoices<F> = {
    create: (organizationId, input, lines) => {
      const { fields: extra, ...rest } = input;
      const amounts = (lines ?? []).map((line) => line.unitAmount);
      const invalid = amountsError(input.currency, amounts);

      if (invalid !== undefined) {
        return AsyncResult.err(invalid);
      }

      const currency = input.currency ?? amounts[0]?.currency;

      return AsyncResult.from(() => fields.write({ ...extra })).andThen(
        (valid) =>
          invoice("create_invoice", {
            tenant: organizationId,
            attrs: attrsArg({
              ...rest,
              ...(currency === undefined ? {} : { currency }),
              ...valid,
            }),
            lines: lines === undefined ? null : lines.map(lineArg),
          }),
      );
    },
    setLines: (invoiceId, lines) => {
      const invalid = amountsError(
        undefined,
        lines.map((line) => line.unitAmount),
      );

      return invalid === undefined
        ? call(
            "set_invoice_lines",
            { parent: invoiceId, lines: lines.map(lineArg) },
            (value) => totalsOf(recordOf(value, "set_invoice_lines"), true),
          )
        : AsyncResult.err(invalid);
    },
    issue: (invoiceId, issuedOn) =>
      invoice("issue_invoice", {
        invoice: invoiceId,
        issued_on: issuedOn === undefined ? null : issuedOn.toString(),
      }),
    recordPayment: (invoiceId, payment) =>
      invoice("record_invoice_payment", {
        invoice: invoiceId,
        amount: amountText(payment.amount),
        currency: payment.amount.currency,
        paid_at: instantArg(payment.paidAt) ?? null,
        method: payment.method ?? null,
        reference: payment.reference ?? null,
      }),
    credit: (invoiceId, credit = {}) => {
      const invalid = amountsError(
        undefined,
        (credit.lines ?? []).map((line) => line.unitAmount),
      );

      return invalid === undefined
        ? invoice("credit_invoice", {
            invoice: invoiceId,
            lines:
              credit.lines === undefined ? null : credit.lines.map(lineArg),
            note: credit.note ?? null,
          })
        : AsyncResult.err(invalid);
    },
    void: (invoiceId, reason) =>
      invoice("void_invoice", { invoice: invoiceId, reason: reason ?? null }),
    writeOff: (invoiceId) =>
      invoice("write_off_invoice", { invoice: invoiceId }),
    charge: (invoiceId, charge) =>
      invoice("add_invoice_charge", {
        invoice: invoiceId,
        amount: amountText(charge.amount),
        currency: charge.amount.currency,
        description: charge.description ?? null,
        fields: charge.fields,
      }),
    aging: (organizationId, currency, asOf) =>
      amountsError(currency, []) === undefined
        ? call(
            "invoice_aging",
            {
              tenant: organizationId,
              currency,
              as_of: asOf === undefined ? null : asOf.toString(),
            },
            (value) => {
              const row = recordOf(value, "invoice_aging");
              const owed = textOf(row["currency"]);

              const at = (key: string): Money =>
                moneyOf(row[key], owed, `invoice_aging ${key}`);

              return {
                currency: owed,
                current: at("current"),
                days1To30: at("days1To30"),
                days31To60: at("days31To60"),
                days61To90: at("days61To90"),
                over90: at("over90"),
                outstanding: at("outstanding"),
                overdueCount: Number(row["overdueCount"] ?? 0),
              };
            },
          )
        : AsyncResult.err(unknownCurrency(currency)),
    fromQuote: (quoteId, fromQuote = {}) =>
      invoice("invoice_from_quote", {
        quote: quoteId,
        deposit_bps: fromQuote.depositBps ?? null,
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "invoices",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
