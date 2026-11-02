import type { Money } from "../../commerce/money.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall, TransitionActor } from "../shared.ts";

import { amountText, moneyOf } from "../money-codec.ts";
import { compact, plainDate } from "../sales-shared.ts";
import {
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/** Whether an open item belongs to a customer or a supplier. */
export type OpenItemSide = "customer" | "supplier";

/** How far past its due date an open item is. */
export type OpenItemBucket =
  | "current"
  | "days1To30"
  | "days31To60"
  | "days61To90"
  | "over90"
  | "unallocated";

const BUCKETS: readonly OpenItemBucket[] = [
  "current",
  "days1To30",
  "days31To60",
  "days61To90",
  "over90",
  "unallocated",
];

/** Where a purchase invoice stands in approval. */
export type InvoiceApprovalStatus = "not_required" | "pending" | "approved";

/** One invoice, bill or unallocated payment a party still has open. */
export interface OpenItem {
  readonly side: OpenItemSide;
  readonly partyId: string;
  /**
   * `unallocated_payment` is cash or credit a party holds that no document uses
   * yet.
   */
  readonly documentType: "invoice" | "unallocated_payment";
  readonly documentId: string;
  /** The document number or payment reference. */
  readonly identifier?: string;
  readonly issuedOn?: Temporal.PlainDate;
  readonly dueOn?: Temporal.PlainDate;
  /** The document total. */
  readonly amount: Money;
  /** What is open as of the date; negative for an unallocated payment. */
  readonly balance: Money;
  readonly daysOverdue: number;
  readonly bucket: OpenItemBucket;
  /** The last day the early-payment discount applies. */
  readonly discountDueOn?: Temporal.PlainDate;
  readonly discountAmount?: Money;
  readonly legalEntityId?: string;
  /** Set on supplier bills when approval levels exist. */
  readonly approvalStatus?: InvoiceApprovalStatus;
}

/** A party's open items summed per ageing bucket, in one currency. */
export interface OpenItemAgeing {
  readonly side: OpenItemSide;
  readonly partyId: string;
  readonly current: Money;
  readonly days1To30: Money;
  readonly days31To60: Money;
  readonly days61To90: Money;
  readonly over90: Money;
  /** Payments not allocated yet, as a negative amount. */
  readonly unallocated: Money;
  readonly outstanding: Money;
}

/** What `allocatePayment` covers on one document. */
export interface PaymentAllocationLine {
  readonly invoiceId: string;
  /** Pass `false` to leave an early-payment discount untaken. */
  readonly takeDiscount?: boolean;
  readonly amount: Money;
}

/** A payment or credit and the documents it settles. */
export interface PaymentAllocationInput {
  readonly partyId: string;
  /** Defaults to `customer`. */
  readonly side?: OpenItemSide;
  readonly amount: Money;
  readonly allocations: readonly PaymentAllocationLine[];
  readonly receivedOn?: Temporal.PlainDate;
  /** Required and unique per organization, so a replay is added once. */
  readonly reference: string;
  readonly method?: string;
  readonly note?: string;
  /** `credit` draws on the party's credit instead of receiving cash. */
  readonly source?: "payment" | "credit";
  readonly actor?: TransitionActor;
}

/** One allocation row of a payment reference. */
export interface InvoiceAllocation {
  readonly reference?: string;
  readonly invoiceId: string;
  readonly source: "payment" | "credit";
  readonly amount: Money;
  /** The early-payment discount taken with this allocation. */
  readonly discount: Money;
  readonly paymentId?: string;
  readonly allocatedOn?: Temporal.PlainDate;
  /** Set once `unallocatePayment` reversed it. */
  readonly unallocatedAt?: Temporal.Instant;
}

/** What `allocatePayment` did. */
export interface PaymentAllocation {
  readonly reference: string;
  readonly partyId: string;
  readonly allocated: Money;
  readonly discount: Money;
  /** The rest of a customer payment, kept as the party's credit. */
  readonly credited?: Money;
  readonly allocations: readonly InvoiceAllocation[];
}

/** One approval level: bills from `minAmount` up need this approver. */
export interface InvoiceApprovalLevel {
  /** 1 for the lowest amount; levels number by `minAmount`. */
  readonly level: number;
  readonly legalEntityId?: string;
  /** In minor units. */
  readonly minAmount: bigint;
  /** Limits the level to one currency; unset applies to every currency. */
  readonly currency?: string;
  readonly approverId: string;
}

/** A level as `setInvoiceApprovalLevels` takes it. */
export interface InvoiceApprovalLevelInput {
  readonly minAmount: bigint;
  readonly currency?: string;
  readonly approverId: string;
}

/** The approval of a purchase invoice. */
export interface InvoiceApproval {
  readonly status: InvoiceApprovalStatus;
  /** The levels the bill's amount requires. */
  readonly required: readonly number[];
  readonly approved: readonly number[];
  readonly pending: readonly {
    readonly level: number;
    readonly approverId: string;
  }[];
}

/** The header totals of an invoice, in minor units. */
export interface InvoiceTotalsSnapshot {
  readonly listTotal?: Money;
  readonly discountTotal?: Money;
  readonly subtotal: Money;
  readonly taxTotal: Money;
  readonly total: Money;
}

/** One invoice whose totals `recomputeTotals` found to differ. */
export interface InvoiceTotalsCorrection {
  readonly invoiceId: string;
  readonly identifier?: string;
  readonly status: string;
  /** The totals stored on the invoice. */
  readonly old: InvoiceTotalsSnapshot;
  /** The totals its lines and credit restriction give. */
  readonly new: InvoiceTotalsSnapshot;
  readonly balance: Money;
  readonly balanceAfter: Money;
  readonly ledger: {
    /** Whether a posted accounting entry books the invoice. */
    readonly posted: boolean;
    readonly entryId?: string;
    readonly entryNumber?: string;
    /** The status of the entry's accounting period. */
    readonly periodStatus?: string;
    /** The posted entry books the old amounts and is not changed. */
    readonly needsCorrectingEntry: boolean;
  };
}

/** What `recomputeTotals` checked and corrected. */
export interface InvoiceTotalsRepair {
  readonly dryRun: boolean;
  readonly checked: number;
  readonly changed: number;
  /** How many invoices were written; zero on a dry run. */
  readonly applied: number;
  readonly invoices: readonly InvoiceTotalsCorrection[];
}

/** Open items, payment allocation and purchase approval on invoices. */
export interface InvoiceOpenItems<I> {
  /**
   * What a party owes or is owed as of a date (default today): open invoices
   * and bills, and unallocated payments as negative balances. Omit `partyId`
   * for every party of the organization.
   */
  openItems(
    input: { organizationId: string } & {
      readonly partyId?: string;
      readonly asOf?: Temporal.PlainDate;
      readonly side?: OpenItemSide;
    },
  ): AsyncResult<readonly OpenItem[]>;
  /** Open items summed per party, currency and ageing bucket. */
  openItemAgeing(
    input: { organizationId: string } & {
      readonly asOf?: Temporal.PlainDate;
      readonly side?: OpenItemSide;
    },
  ): AsyncResult<readonly OpenItemAgeing[]>;
  /**
   * Allocates one payment or credit to several documents. An allocation under
   * the balance is a partial payment, and one that arrives by the discount date
   * takes the early-payment discount. A replay of the same reference adds
   * nothing.
   */
  allocatePayment(input: {
    organizationId: string;
    payment: PaymentAllocationInput;
  }): AsyncResult<PaymentAllocation>;
  /** Reverses every allocation of a reference; the invoices reopen. */
  unallocatePayment(
    input: { organizationId: string; reference: string } & {
      readonly actor?: TransitionActor;
    },
  ): AsyncResult<number>;
  /** The allocations of a payment reference or of one invoice. */
  allocations(
    input: { organizationId: string } & {
      readonly reference?: string;
      readonly invoiceId?: string;
    },
  ): AsyncResult<readonly InvoiceAllocation[]>;
  /** The approval levels of an organization. */
  approvalLevels(
    organizationId: string,
  ): AsyncResult<readonly InvoiceApprovalLevel[]>;
  /** Replaces the levels of an organization, or of one legal entity. */
  setApprovalLevels(
    input: {
      organizationId: string;
      levels: readonly InvoiceApprovalLevelInput[];
    } & { readonly legalEntityId?: string },
  ): AsyncResult<readonly InvoiceApprovalLevel[]>;
  /** Where a purchase invoice stands in approval. */
  approvalStatus(invoiceId: string): AsyncResult<InvoiceApproval>;
  /**
   * Approves the levels the signed-in user is the approver of. Needs
   * `invoices.approve`. Payment batches skip bills until every level is done.
   */
  approvePurchaseInvoice(
    input: { invoiceId: string } & { readonly comment?: string },
  ): AsyncResult<I>;
  /**
   * Recounts the header totals of issued invoices with the credit restriction
   * of their payment terms, for invoices issued before the totals followed it.
   * A dry run (the default) only reports the old and new totals. Applying
   * writes the totals and tax lines of the invoices that differ, never a
   * number, date or status, and audits each as a system correction. A posted
   * accounting entry is not changed; the report marks it as needing a
   * correcting entry. Running it again changes nothing. Needs
   * `invoices.manage`.
   */
  recomputeTotals(
    input: { organizationId: string } & {
      /** Limits the repair to these invoices; unset checks every issued one. */
      readonly invoiceIds?: readonly string[];
      /** Defaults to `true`. */
      readonly dryRun?: boolean;
    },
  ): AsyncResult<InvoiceTotalsRepair>;
}

function sideOf(value: unknown): OpenItemSide {
  return value === "supplier" ? "supplier" : "customer";
}

function bucketOf(value: unknown): OpenItemBucket {
  const found = BUCKETS.find((bucket) => bucket === value);

  if (found === undefined) {
    throw new TypeError(`Unknown open item bucket: ${String(value)}`);
  }

  return found;
}

function statusOf(value: unknown): InvoiceApprovalStatus {
  return value === "pending" || value === "approved" ? value : "not_required";
}

function openItemOf(row: Readonly<Record<string, unknown>>): OpenItem {
  const currency = textOf(row["currency"]);
  const kind = row["documentType"];
  const discount = row["discountAmount"];

  return compact<OpenItem>({
    side: sideOf(row["side"]),
    partyId: textOf(row["partyId"]),
    documentType: kind === "unallocated_payment" ? kind : "invoice",
    documentId: textOf(row["documentId"]),
    identifier: optionalText(row["identifier"]),
    issuedOn: plainDate(row["issuedOn"]),
    dueOn: plainDate(row["dueOn"]),
    amount: moneyOf(row["amount"], currency, "open item amount"),
    balance: moneyOf(row["balance"], currency, "open item balance"),
    daysOverdue: Number(row["daysOverdue"] ?? 0),
    bucket: bucketOf(row["bucket"]),
    discountDueOn: plainDate(row["discountDueOn"]),
    discountAmount:
      discount === null || discount === undefined
        ? undefined
        : moneyOf(discount, currency, "open item discount"),
    legalEntityId: optionalText(row["legalEntityId"]),
    approvalStatus:
      row["approvalStatus"] === null || row["approvalStatus"] === undefined
        ? undefined
        : statusOf(row["approvalStatus"]),
  });
}

function ageingOf(value: unknown): readonly OpenItemAgeing[] {
  return recordsOf(value, "open item ageing").map((row) => {
    const currency = textOf(row["currency"]);

    const at = (key: string): Money =>
      moneyOf(row[key], currency, `open item ageing ${key}`);

    return {
      side: sideOf(row["side"]),
      partyId: textOf(row["partyId"]),
      current: at("current"),
      days1To30: at("days1To30"),
      days31To60: at("days31To60"),
      days61To90: at("days61To90"),
      over90: at("over90"),
      unallocated: at("unallocated"),
      outstanding: at("outstanding"),
    };
  });
}

function allocationsOf(
  value: unknown,
  currencyOf: (row: Readonly<Record<string, unknown>>) => string,
): readonly InvoiceAllocation[] {
  return recordsOf(value, "invoice allocations").map((row) => {
    const currency = currencyOf(row);

    return compact<InvoiceAllocation>({
      reference: optionalText(row["reference"]),
      invoiceId: textOf(row["invoiceId"]),
      source: row["source"] === "credit" ? "credit" : "payment",
      amount: moneyOf(row["amount"], currency, "allocation amount"),
      discount: moneyOf(row["discount"], currency, "allocation discount"),
      paymentId: optionalText(row["paymentId"]),
      allocatedOn: plainDate(row["allocatedOn"]),
      unallocatedAt: optionalInstant(row["unallocatedAt"]),
    });
  });
}

function levelsOf(value: unknown): readonly InvoiceApprovalLevel[] {
  return recordsOf(value, "invoice approval levels").map((row) =>
    compact<InvoiceApprovalLevel>({
      level: Number(row["level"]),
      legalEntityId: optionalText(row["legalEntityId"]),
      minAmount: BigInt(textOf(row["minAmount"])),
      currency: optionalText(row["currency"]),
      approverId: textOf(row["approverId"]),
    }),
  );
}

function snapshotOf(value: unknown, currency: string): InvoiceTotalsSnapshot {
  const row = recordOf(value, "invoice totals");

  const at = (key: string): Money =>
    moneyOf(row[key], currency, `invoice totals ${key}`);

  return compact<InvoiceTotalsSnapshot>({
    listTotal: row["listTotal"] === undefined ? undefined : at("listTotal"),
    discountTotal:
      row["discountTotal"] === undefined ? undefined : at("discountTotal"),
    subtotal: at("subtotal"),
    taxTotal: at("taxTotal"),
    total: at("total"),
  });
}

function repairOf(value: unknown): InvoiceTotalsRepair {
  const row = recordOf(value, "invoice totals repair");

  return {
    dryRun: row["dryRun"] === true,
    checked: Number(row["checked"]),
    changed: Number(row["changed"]),
    applied: Number(row["applied"]),
    invoices: recordsOf(row["invoices"], "invoice totals corrections").map(
      (entry) => {
        const currency = textOf(entry["currency"]);
        const ledger = recordOf(entry["ledger"], "invoice totals ledger");

        return compact<InvoiceTotalsCorrection>({
          invoiceId: textOf(entry["invoiceId"]),
          identifier: optionalText(entry["identifier"]),
          status: textOf(entry["status"]),
          old: snapshotOf(entry["old"], currency),
          new: snapshotOf(entry["new"], currency),
          balance: moneyOf(entry["balance"], currency, "invoice balance"),
          balanceAfter: moneyOf(
            entry["balanceAfter"],
            currency,
            "invoice balance after",
          ),
          ledger: compact({
            posted: ledger["posted"] === true,
            entryId: optionalText(ledger["entryId"]),
            entryNumber: optionalText(ledger["entryNumber"]),
            periodStatus: optionalText(ledger["periodStatus"]),
            needsCorrectingEntry: ledger["needsCorrectingEntry"] === true,
          }),
        });
      },
    ),
  };
}

function approvalOf(value: unknown): InvoiceApproval {
  const row = recordOf(value, "invoice approval");

  const levels = (key: string): readonly number[] =>
    Array.isArray(row[key]) ? row[key].map(Number) : [];

  return {
    status: statusOf(row["status"]),
    required: levels("required"),
    approved: levels("approved"),
    pending: recordsOf(row["pending"], "pending approvals").map((level) => ({
      level: Number(level["level"]),
      approverId: textOf(level["approverId"]),
    })),
  };
}

/** The open item and approval methods of the invoices client. */
export function invoiceOpenItems<I>(
  call: BlockCall,
  invoice: (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ) => AsyncResult<I>,
): InvoiceOpenItems<I> {
  return {
    openItems: ({ organizationId, ...options }) =>
      call(
        "open_items_for_party",
        {
          tenant: organizationId,
          party_id: options.partyId ?? null,
          as_of: options.asOf?.toString() ?? null,
          side: options.side ?? null,
        },
        (value) => recordsOf(value, "open items").map(openItemOf),
      ),
    openItemAgeing: ({ organizationId, ...options }) =>
      call(
        "open_item_ageing",
        {
          tenant: organizationId,
          side: options.side ?? null,
          as_of: options.asOf?.toString() ?? null,
        },
        ageingOf,
      ),
    allocatePayment: ({ organizationId, payment }) =>
      call(
        "allocate_payment",
        {
          tenant: organizationId,
          payment: {
            partyId: payment.partyId,
            side: payment.side ?? "customer",
            amount: amountText(payment.amount),
            currency: payment.amount.currency,
            receivedOn: payment.receivedOn?.toString() ?? null,
            reference: payment.reference,
            method: payment.method ?? null,
            note: payment.note ?? null,
            source: payment.source ?? "payment",
          },
          allocations: payment.allocations.map((part) => ({
            invoiceId: part.invoiceId,
            amount: amountText(part.amount),
            takeDiscount: part.takeDiscount ?? true,
          })),
          ...(payment.actor === undefined ? {} : { actor: payment.actor }),
        },
        (value) => {
          const row = recordOf(value, "allocate_payment");
          const currency = textOf(row["currency"]);
          const credited = row["credited"];

          return compact<PaymentAllocation>({
            reference: textOf(row["reference"]),
            partyId: textOf(row["partyId"]),
            allocated: moneyOf(row["allocated"], currency, "allocated"),
            discount: moneyOf(row["discount"], currency, "discount"),
            credited:
              credited === undefined || credited === null
                ? undefined
                : moneyOf(credited, currency, "credited"),
            allocations: allocationsOf(row["allocations"], () => currency),
          });
        },
      ),
    unallocatePayment: ({ organizationId, reference, ...options }) =>
      call(
        "unallocate_payment",
        {
          tenant: organizationId,
          reference,
          ...(options.actor === undefined ? {} : { actor: options.actor }),
        },
        (value) => Number(recordOf(value, "unallocate_payment")["unallocated"]),
      ),
    allocations: ({ organizationId, ...options }) =>
      call(
        "list_invoice_allocations",
        {
          tenant: organizationId,
          reference: options.reference ?? null,
          invoice_id: options.invoiceId ?? null,
        },
        (value) => allocationsOf(value, (row) => textOf(row["currency"])),
      ),
    approvalLevels: (organizationId) =>
      call(
        "list_invoice_approval_levels",
        { tenant: organizationId },
        levelsOf,
      ),
    setApprovalLevels: ({ organizationId, levels, ...options }) =>
      call(
        "set_invoice_approval_levels",
        {
          tenant: organizationId,
          levels: levels.map((level) => ({
            minAmount: level.minAmount.toString(),
            ...(level.currency === undefined
              ? {}
              : { currency: level.currency }),
            approverId: level.approverId,
          })),
          legal_entity_id: options.legalEntityId ?? null,
        },
        levelsOf,
      ),
    approvalStatus: (invoiceId) =>
      call(
        "purchase_invoice_approval_status",
        { invoice: invoiceId },
        approvalOf,
      ),
    approvePurchaseInvoice: ({ invoiceId, ...options }) =>
      invoice("approve_purchase_invoice", {
        invoice: invoiceId,
        comment: options.comment ?? null,
      }),
    recomputeTotals: ({ organizationId, ...options }) =>
      call(
        "recompute_invoice_totals",
        {
          tenant: organizationId,
          invoice_ids: options.invoiceIds ?? null,
          dry_run: options.dryRun ?? true,
        },
        repairOf,
      ),
  };
}
