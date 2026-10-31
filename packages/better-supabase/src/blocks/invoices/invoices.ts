import type { Money } from "../../commerce/money.ts";
import type { BlockFields, FieldsOf } from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { BlockTransport } from "../../core/block-transport.ts";
import type { ErrorMapper } from "../../core/errors.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { Line, LineInput, Totals } from "../sales-lines.ts";
import type { RecordRef } from "../sales-shared.ts";
import type { BlockTemporalOptions, TransitionActor } from "../shared.ts";
import type { InvoiceCollections, InvoiceDunning } from "./collections.ts";

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
import { DUNNING_KEYS, dunningOf, invoiceCollections } from "./collections.ts";

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
  /** The note given when it was recorded. */
  readonly note?: string;
  /** The user who recorded it. */
  readonly recordedBy?: string;
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

/** `sales` for what customers owe, `purchase` for a bill from a supplier. */
export type InvoiceDirection = "sales" | "purchase";

/** How a purchase bill compares with its purchase order and receipts. */
export type InvoiceMatchStatus =
  | "matched"
  | "price_variance"
  | "quantity_variance"
  | "not_received"
  | "not_applicable";

const MATCH_STATUSES: readonly InvoiceMatchStatus[] = [
  "matched",
  "price_variance",
  "quantity_variance",
  "not_received",
  "not_applicable",
];

/** One billed variant of a three-way match. Quantities are base units. */
export interface InvoiceMatchLine {
  readonly variantId: string;
  /** Billed on this bill. */
  readonly quantity: string;
  /** Billed across the purchase order's bills. */
  readonly billedQuantity: string;
  readonly orderedQuantity: string;
  readonly receivedQuantity: string;
  /** This bill's net amount for the variant. */
  readonly amount: Money;
  /** The quantity at the purchase order's unit cost. */
  readonly expectedAmount: Money;
  readonly status: Exclude<InvoiceMatchStatus, "not_applicable">;
}

/** The three-way match of a purchase bill; the worst line decides. */
export interface InvoiceMatch {
  readonly invoiceId: string;
  readonly purchaseOrderId?: string;
  readonly status: InvoiceMatchStatus;
  readonly lines: readonly InvoiceMatchLine[];
}

/** An invoice. `F` types the extra columns the `fields` schema describes. */
export interface Invoice<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly kind: "invoice" | "credit_note";
  /** `sales` unless the invoice is a purchase bill. */
  readonly direction: InvoiceDirection;
  /** The supplier's own number on a purchase bill. */
  readonly supplierReference?: string;
  /** The inventory purchase order a purchase bill bills. */
  readonly purchaseOrderId?: string;
  /** Accounting dimension codes by dimension key, such as `project`. */
  readonly dimensions?: Readonly<Record<string, string>>;
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
  /** For a fixed deposit invoice: its amount, tax included. */
  readonly depositAmount?: Money;
  /** A percentage off the whole invoice, when the table has the column. */
  readonly discountBps?: number;
  /** An amount off the whole invoice, after `discountBps`. */
  readonly discountAmount?: Money;
  /** Unit amounts include tax, so tax is counted out of them. */
  readonly pricesIncludeTax: boolean;
  /** Reminder level and pause, when the table has the dunning columns. */
  readonly dunning?: InvoiceDunning;
  readonly lines: readonly Line[];
  readonly payments: readonly InvoicePayment[];
  readonly totals: Totals;
  /** The app's extra columns (`options.extraColumns`), by column name. */
  readonly fields: Readonly<Record<string, unknown>> & F;
  readonly createdAt: Temporal.Instant;
}

export interface InvoiceInput<F extends object = Record<never, never>> {
  readonly title: string;
  /**
   * `purchase` for a bill from the supplier in `company` or `contact`. Needs
   * `invoices.purchase`; defaults to `sales`.
   */
  readonly direction?: InvoiceDirection;
  readonly supplierReference?: string;
  /** An inventory purchase order of the organization, for the match. */
  readonly purchaseOrderId?: string;
  /** Accounting dimension codes by key; the expense lines carry them. */
  readonly dimensions?: Readonly<Record<string, string>>;
  /** Defaults to the lines' currency, then `EUR`. */
  readonly currency?: string;
  readonly company?: RecordRef;
  readonly contact?: RecordRef;
  readonly termsDays?: number;
  readonly note?: string;
  readonly origin?: RecordRef;
  /** Unit amounts include tax. Needs the `prices_include_tax` column. */
  readonly pricesIncludeTax?: boolean;
  /** A percentage off the whole invoice. Needs the `discountBps` column. */
  readonly discountBps?: number;
  /** An amount off the whole invoice. Needs the `discountAmount` column. */
  readonly discountAmount?: Money;
  /** Values for the extra columns, by column name. */
  readonly fields?: Partial<F> & Readonly<Record<string, unknown>>;
}

export interface InvoicePatch<F extends object = Record<never, never>> {
  readonly title?: string;
  readonly company?: RecordRef | null;
  readonly contact?: RecordRef | null;
  readonly termsDays?: number | null;
  readonly note?: string | null;
  readonly depositBps?: number | null;
  readonly pricesIncludeTax?: boolean;
  readonly discountBps?: number;
  readonly discountAmount?: Money;
  readonly supplierReference?: string | null;
  readonly purchaseOrderId?: string | null;
  readonly dimensions?: Readonly<Record<string, string>> | null;
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
/** Who made a status change, for the state machine's history. */
export interface InvoiceActorOptions {
  readonly actor?: TransitionActor;
}

const actorArg = (
  actor: TransitionActor | undefined,
): { readonly actor?: TransitionActor } =>
  actor === undefined ? {} : { actor };

export interface Invoices<
  F extends object = Record<never, never>,
> extends InvoiceCollections<Invoice<F>> {
  create(
    organizationId: string,
    input: InvoiceInput<F>,
    lines?: readonly LineInput[],
  ): AsyncResult<Invoice<F>>;
  update(invoiceId: string, patch: InvoicePatch<F>): AsyncResult<Invoice<F>>;
  delete(invoiceId: string): AsyncResult<boolean>;
  setLines(invoiceId: string, lines: readonly LineInput[]): AsyncResult<Totals>;
  /** Issues a draft: the next number, issue and due dates, frozen lines. */
  issue(
    invoiceId: string,
    issuedOn?: Temporal.PlainDate,
    options?: {
      readonly dueOn?: Temporal.PlainDate;
      /** Who issued it, for the state machine's history. */
      readonly actor?: TransitionActor;
    },
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
      /** A memo kept with the payment. */
      readonly note?: string;
      /** Who recorded it, for the state machine's history. */
      readonly actor?: TransitionActor;
      /**
       * Why the status changes, such as a refund, for the state machine's
       * history.
       */
      readonly reason?: string;
    },
  ): AsyncResult<Invoice<F>>;
  /** A draft credit note for the whole invoice, or for the given lines. */
  credit(
    invoiceId: string,
    options?: { readonly lines?: readonly LineInput[]; readonly note?: string },
  ): AsyncResult<Invoice<F>>;
  /** The reason and `actor` go to the state machine's history. */
  void(
    invoiceId: string,
    reason?: string,
    options?: InvoiceActorOptions,
  ): AsyncResult<Invoice<F>>;
  /** The reason and `actor` go to the state machine's history. */
  writeOff(
    invoiceId: string,
    reason?: string,
    options?: InvoiceActorOptions,
  ): AsyncResult<Invoice<F>>;
  /** The reason and `actor` go to the state machine's history. */
  reversePayment(
    paymentId: string,
    reason?: string,
    options?: InvoiceActorOptions,
  ): AsyncResult<Invoice<F>>;
  removeCharge(
    chargeId: string,
    options?: InvoiceActorOptions,
  ): AsyncResult<Invoice<F>>;
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
      /** Who added it, for the state machine's history. */
      readonly actor?: TransitionActor;
    },
  ): AsyncResult<Invoice<F>>;
  /**
   * What customers owe (`sales`, the default) or what the organization owes its
   * suppliers (`purchase`), by days past due.
   */
  aging(
    organizationId: string,
    currency: string,
    asOf?: Temporal.PlainDate,
    direction?: InvoiceDirection,
  ): AsyncResult<InvoiceAging>;
  /**
   * Runs the three-way match of a purchase bill against its purchase order and
   * receipts, and records `invoice.match_checked`.
   */
  match(invoiceId: string): AsyncResult<InvoiceMatch>;
  payments(invoiceId: string): AsyncResult<readonly InvoicePayment[]>;
  /**
   * An invoice from an accepted quote: the full invoice once, minus the
   * deposits already issued, or a deposit invoice for `depositBps` of it or a
   * fixed `depositAmount`, tax included.
   */
  fromQuote(
    quoteId: string,
    options?: {
      readonly depositBps?: number;
      readonly depositAmount?: Money;
      readonly depositDescription?: string;
    },
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
  "deposit_amount",
  "discount_bps",
  "discount_amount",
  "prices_include_tax",
  "direction",
  "supplier_reference",
  "purchase_order_id",
  "dimensions",
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
  ...DUNNING_KEYS,
]);

function paymentOf(
  payment: Readonly<Record<string, unknown>>,
  currency: string,
): InvoicePayment {
  return compact<InvoicePayment>({
    id: textOf(payment["id"]),
    amount: moneyOf(payment["amount"], currency, "invoice payment amount"),
    paidAt: requiredInstant(payment["paidAt"], "paidAt"),
    method: optionalText(payment["method"]),
    reference: optionalText(payment["reference"]),
    note: optionalText(payment["note"]),
    recordedBy: optionalText(payment["recordedBy"]),
  });
}

function dimensionsOf(
  value: unknown,
): Readonly<Record<string, string>> | undefined {
  if (!isRecord(value)) {
    return undefined;
  }

  const entries = Object.entries(value).filter(
    (entry): entry is [string, string] => typeof entry[1] === "string",
  );

  return entries.length === 0 ? undefined : Object.fromEntries(entries);
}

function matchOf(value: unknown): InvoiceMatch {
  const row = recordOf(value, "purchase_bill_match");
  const currency = textOf(row["currency"]);

  return compact<InvoiceMatch>({
    invoiceId: textOf(row["invoiceId"]),
    purchaseOrderId: optionalText(row["purchaseOrderId"]),
    status: enumOrThrow(row["status"], MATCH_STATUSES, "invoice match status"),
    lines: recordsOf(row["lines"], "invoice match lines").map((line) => ({
      variantId: textOf(line["variantId"]),
      quantity: textOf(line["quantity"]),
      billedQuantity: textOf(line["billedQuantity"]),
      orderedQuantity: textOf(line["orderedQuantity"]),
      receivedQuantity: textOf(line["receivedQuantity"]),
      amount: moneyOf(line["amount"], currency, "invoice match amount"),
      expectedAmount: moneyOf(
        line["expectedAmount"],
        currency,
        "invoice match expectedAmount",
      ),
      status: enumOrThrow(
        line["status"],
        ["matched", "price_variance", "quantity_variance", "not_received"],
        "invoice match line status",
      ),
    })),
  });
}

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
    direction: row["direction"] === "purchase" ? "purchase" : "sales",
    supplierReference: optionalText(row["supplier_reference"]),
    purchaseOrderId: optionalText(row["purchase_order_id"]),
    dimensions: dimensionsOf(row["dimensions"]),
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
    depositAmount:
      typeof row["deposit_amount"] === "string"
        ? moneyOf(row["deposit_amount"], currency, "invoice depositAmount")
        : undefined,
    discountBps:
      typeof row["discount_bps"] === "number" ? row["discount_bps"] : undefined,
    discountAmount:
      typeof row["discount_amount"] === "string"
        ? moneyOf(row["discount_amount"], currency, "invoice discountAmount")
        : undefined,
    pricesIncludeTax: row["prices_include_tax"] === true,
    dunning: dunningOf(row),
    lines: recordsOf(row["lines"], "invoice lines").map((line) =>
      lineOf(line, currency),
    ),
    payments: recordsOf(row["payments"], "invoice payments").map((payment) =>
      paymentOf(payment, currency),
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
      const { fields: extra, discountAmount, ...rest } = input;
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
              ...(discountAmount === undefined
                ? {}
                : { discountAmount: amountText(discountAmount) }),
              ...valid,
            }),
            lines: lines === undefined ? null : lines.map(lineArg),
          }),
      );
    },
    update: (invoiceId, patch) => {
      const { fields: extra, discountAmount, ...rest } = patch;

      return AsyncResult.from(() => fields.write({ ...extra })).andThen(
        (valid) =>
          invoice("update_invoice", {
            invoice: invoiceId,
            attrs: attrsArg({
              ...rest,
              ...(discountAmount === undefined
                ? {}
                : { discountAmount: amountText(discountAmount) }),
              ...valid,
            }),
          }),
      );
    },
    delete: (invoiceId) =>
      call("delete_invoice", { invoice: invoiceId }, (value) => value === true),
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
    issue: (invoiceId, issuedOn, issueOptions = {}) =>
      invoice("issue_invoice", {
        invoice: invoiceId,
        issued_on: issuedOn === undefined ? null : issuedOn.toString(),
        ...(issueOptions.dueOn === undefined
          ? {}
          : { due_on: issueOptions.dueOn.toString() }),
        ...(issueOptions.actor === undefined
          ? {}
          : { actor: issueOptions.actor }),
      }),
    recordPayment: (invoiceId, payment) =>
      invoice("record_invoice_payment", {
        invoice: invoiceId,
        amount: amountText(payment.amount),
        currency: payment.amount.currency,
        paid_at: instantArg(payment.paidAt) ?? null,
        method: payment.method ?? null,
        reference: payment.reference ?? null,
        note: payment.note ?? null,
        ...(payment.actor === undefined ? {} : { actor: payment.actor }),
        ...(payment.reason === undefined ? {} : { reason: payment.reason }),
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
    void: (invoiceId, reason, actorOptions) =>
      invoice("void_invoice", {
        invoice: invoiceId,
        reason: reason ?? null,
        ...actorArg(actorOptions?.actor),
      }),
    writeOff: (invoiceId, reason, actorOptions) =>
      invoice("write_off_invoice", {
        invoice: invoiceId,
        reason: reason ?? null,
        ...actorArg(actorOptions?.actor),
      }),
    reversePayment: (paymentId, reason, actorOptions) =>
      invoice("reverse_invoice_payment", {
        payment: paymentId,
        reason: reason ?? null,
        ...actorArg(actorOptions?.actor),
      }),
    removeCharge: (chargeId, actorOptions) =>
      invoice("remove_invoice_charge", {
        charge: chargeId,
        ...actorArg(actorOptions?.actor),
      }),
    charge: (invoiceId, charge) =>
      invoice("add_invoice_charge", {
        invoice: invoiceId,
        amount: amountText(charge.amount),
        currency: charge.amount.currency,
        description: charge.description ?? null,
        fields: charge.fields,
        ...actorArg(charge.actor),
      }),
    aging: (organizationId, currency, asOf, direction) =>
      amountsError(currency, []) === undefined
        ? call(
            "invoice_aging",
            {
              tenant: organizationId,
              currency,
              as_of: asOf === undefined ? null : asOf.toString(),
              ...(direction === undefined ? {} : { direction }),
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
    ...invoiceCollections(call, invoice),
    match: (invoiceId) =>
      call("purchase_bill_match", { invoice: invoiceId }, matchOf),
    payments: (invoiceId) =>
      call("list_invoice_payments", { invoice: invoiceId }, (value) => {
        const row = recordOf(value, "list_invoice_payments");
        const currency = textOf(row["currency"]);

        return recordsOf(row["payments"], "invoice payments").map((payment) =>
          paymentOf(payment, currency),
        );
      }),
    fromQuote: (quoteId, fromQuote = {}) =>
      invoice("invoice_from_quote", {
        quote: quoteId,
        deposit_bps: fromQuote.depositBps ?? null,
        ...(fromQuote.depositAmount === undefined
          ? {}
          : { deposit_amount: amountText(fromQuote.depositAmount) }),
        ...(fromQuote.depositDescription === undefined
          ? {}
          : { deposit_description: fromQuote.depositDescription }),
      }),
  };

  return withBlockHooks(client, options.hooks, {
    block: "invoices",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
