import type { Money } from "../../commerce/money.ts";
import type { AsyncResult } from "../../core/result.ts";
import type { BlockCall, TransitionActor } from "../shared.ts";

import { amountText, moneyOf } from "../money-codec.ts";
import { compact, plainDate } from "../sales-shared.ts";
import {
  bigintOf,
  optionalInstant,
  optionalText,
  recordOf,
  recordsOf,
  textOf,
} from "../shared.ts";

/** Where an invoice stands in dunning, when the table keeps it. */
export interface InvoiceDunning {
  /** The reminder level reached; 0 before the first reminder. */
  readonly level: number;
  /** When the invoice reached that level. */
  readonly at?: Temporal.Instant;
  /** Reminders wait until after this date, such as during a dispute. */
  readonly pausedUntil?: Temporal.PlainDate;
}

/** The payment terms an invoice copied and the early-payment discount they give. */
export interface InvoicePaymentTerms {
  readonly id: string;
  /** The last day the early-payment discount applies; set on issue. */
  readonly discountDueOn?: Temporal.PlainDate;
  /** What the buyer may deduct when paying by `discountDueOn`; set on issue. */
  readonly discountAmount?: Money;
}

/** An invoice handed over to a collection agency. */
export interface InvoiceCollection {
  readonly status: "handed_over";
  /** The company or person that collects. */
  readonly agencyPartyId: string;
  readonly handedOverAt?: Temporal.Instant;
}

/** One reminder step of an organization's dunning. */
export interface InvoiceDunningLevel {
  /** 1 for the first reminder, in the order the levels were set. */
  readonly level: number;
  /** Days past the due date the level is reached. */
  readonly daysAfterDue: number;
  /** The template the reminder for this level is rendered from. */
  readonly templateKey: string;
  /** The text block of the reminder, when the level names one. */
  readonly textKey?: string;
  /** A fee in minor units of the invoice's currency, added as a charge. */
  readonly fee: bigint;
  /** The last reminder, after which the invoice goes to collection. */
  readonly final: boolean;
}

/** One run of `runDunning` for an organization. */
export interface InvoiceDunningRun {
  readonly id: string;
  /** The date the run measured overdue by. */
  readonly asOf: Temporal.PlainDate;
  readonly createdAt?: Temporal.Instant;
  /** How many invoices the run picked. */
  readonly items: number;
  /** How many customers those invoices belong to. */
  readonly customers: number;
}

/** An invoice a run picked, at the level it reached. */
export interface InvoiceDunningRunItem {
  readonly invoiceId: string;
  readonly level: number;
  readonly textKey?: string;
  readonly templateKey: string;
  readonly fee: bigint;
  /** What was open when the run picked it, in the invoice's currency. */
  readonly balance: bigint;
  readonly dueOn: Temporal.PlainDate;
}

/** What a run picked for one customer. */
export interface InvoiceDunningRunCustomer {
  /** The company or contact id the invoices name; unset without a party. */
  readonly partyId?: string;
  readonly balance: bigint;
  readonly fee: bigint;
  readonly items: readonly InvoiceDunningRunItem[];
}

/** One entry of an invoice's dunning history. */
export interface InvoiceDunningHistoryEntry {
  readonly kind: "reminder" | "handed_over";
  readonly level: number;
  readonly textKey?: string;
  readonly templateKey?: string;
  readonly fee: bigint;
  readonly balance: bigint;
  readonly note?: string;
  readonly runId?: string;
  readonly at: Temporal.Instant;
}

/** A level as `setDunningLevels` takes it; levels number in order. */
export interface InvoiceDunningLevelInput {
  readonly daysAfterDue: number;
  readonly templateKey: string;
  readonly textKey?: string;
  readonly fee?: bigint;
  readonly final?: boolean;
}

/** One payment from a party, split over its invoices. */
export interface PartyPaymentInput {
  /** The company or contact id the invoices name. */
  readonly partyId: string;
  readonly amount: Money;
  /** Each part is recorded as a payment of that invoice. */
  readonly allocations: readonly {
    readonly invoiceId: string;
    readonly amount: Money;
  }[];
  readonly receivedOn?: Temporal.PlainDate;
  /** Required and unique per organization, so a replay is added once. */
  readonly reference: string;
  readonly method?: string;
  readonly note?: string;
  /** Who recorded it, for the state machine's history. */
  readonly actor?: TransitionActor;
}

/** What `recordPartyPayment` did with a payment. */
export interface PartyPayment {
  readonly partyId: string;
  readonly amount: Money;
  readonly allocated: Money;
  /** The rest, kept as the party's credit. */
  readonly credited: Money;
  /** The ledger transaction that kept the rest, when there was one. */
  readonly creditTransactionId?: string;
  /** The party's credit in the payment's currency afterwards. */
  readonly credit: Money;
}

/** Party payments, party credit and dunning on invoices. */
export interface InvoiceCollections<I> {
  /**
   * Records one payment from a party over several of its invoices. What the
   * allocations leave over becomes the party's credit.
   */
  recordPartyPayment(
    organizationId: string,
    payment: PartyPaymentInput,
  ): AsyncResult<PartyPayment>;
  /** Pays an open invoice from its party's credit, in the invoice's currency. */
  applyPartyCredit(
    partyId: string,
    invoiceId: string,
    amount: Money,
    options?: { readonly actor?: TransitionActor },
  ): AsyncResult<I>;
  /** A party's unallocated credit, one amount per currency. */
  partyCredits(
    organizationId: string,
    partyId: string,
  ): AsyncResult<readonly Money[]>;
  dunningLevels(
    organizationId: string,
  ): AsyncResult<readonly InvoiceDunningLevel[]>;
  /** Replaces the organization's reminder levels. */
  setDunningLevels(
    organizationId: string,
    levels: readonly InvoiceDunningLevelInput[],
  ): AsyncResult<readonly InvoiceDunningLevel[]>;
  /**
   * Raises each overdue invoice to the reminder level it reached and records
   * `invoice.dunning_escalated`. Service role only; returns how many moved.
   */
  runDunning(options?: {
    readonly organizationId?: string;
    readonly asOf?: Temporal.PlainDate;
  }): AsyncResult<number>;
  /** The runs of `runDunning` for an organization, newest first. */
  dunningRuns(
    organizationId: string,
    options?: { readonly limit?: number },
  ): AsyncResult<readonly InvoiceDunningRun[]>;
  /** The invoices a run picked, grouped by customer. */
  dunningRunItems(
    runId: string,
  ): AsyncResult<readonly InvoiceDunningRunCustomer[]>;
  /** What happened to an invoice in collections, oldest first. */
  dunningHistory(
    invoiceId: string,
  ): AsyncResult<readonly InvoiceDunningHistoryEntry[]>;
  /**
   * Hands open sales invoices over to a collection agency (1 to 500). Their
   * dunning stops and `collection.status` becomes `handed_over`. Needs
   * `invoices.collect`. Returns the ids handed over.
   */
  handOverToCollection(
    invoiceIds: readonly string[],
    agencyPartyId: string,
    options?: { readonly note?: string },
  ): AsyncResult<readonly string[]>;
  /** Holds an invoice's reminders until a date; `null` resumes them. */
  pauseDunning(
    invoiceId: string,
    until: Temporal.PlainDate | null,
    reason?: string,
  ): AsyncResult<I>;
}

/** The invoice row keys dunning reads. */
export const DUNNING_KEYS: readonly string[] = [
  "dunning_level",
  "dunning_at",
  "dunning_paused_until",
];

/** An invoice row's dunning, or `undefined` when the table has no columns. */
export function dunningOf(
  row: Readonly<Record<string, unknown>>,
): InvoiceDunning | undefined {
  if (typeof row["dunning_level"] !== "number") {
    return undefined;
  }

  return compact<InvoiceDunning>({
    level: row["dunning_level"],
    at: optionalInstant(row["dunning_at"]),
    pausedUntil: plainDate(row["dunning_paused_until"]),
  });
}

/** An invoice row's payment terms, or `undefined` without a terms id. */
export function paymentTermsOf(
  row: Readonly<Record<string, unknown>>,
  currency: string,
): InvoicePaymentTerms | undefined {
  const id = optionalText(row["payment_terms_id"]);

  if (id === undefined) {
    return undefined;
  }

  const early = row["discount_amount_early"];

  return compact<InvoicePaymentTerms>({
    id,
    discountDueOn: plainDate(row["discount_due_on"]),
    discountAmount:
      typeof early === "string" || typeof early === "number"
        ? moneyOf(early, currency, "invoice early discount")
        : undefined,
  });
}

/** An invoice row's hand-over to collection, or `undefined` when none. */
export function collectionOf(
  row: Readonly<Record<string, unknown>>,
): InvoiceCollection | undefined {
  const agency = optionalText(row["collection_agency_id"]);

  if (row["collection_status"] !== "handed_over" || agency === undefined) {
    return undefined;
  }

  return compact<InvoiceCollection>({
    status: "handed_over",
    agencyPartyId: agency,
    handedOverAt: optionalInstant(row["collection_handed_at"]),
  });
}

function runsOf(value: unknown): readonly InvoiceDunningRun[] {
  return recordsOf(value, "invoice dunning runs").map((run) =>
    compact<InvoiceDunningRun>({
      id: textOf(run["id"]),
      asOf: plainDate(run["asOf"]),
      createdAt: optionalInstant(run["createdAt"]),
      items: Number(run["items"]),
      customers: Number(run["customers"]),
    }),
  );
}

function runItemOf(
  item: Readonly<Record<string, unknown>>,
): InvoiceDunningRunItem {
  return compact<InvoiceDunningRunItem>({
    invoiceId: textOf(item["invoiceId"]),
    level: Number(item["level"]),
    textKey: optionalText(item["textKey"]),
    templateKey: textOf(item["templateKey"]),
    fee: bigintOf(item["fee"], "dunning item fee"),
    balance: bigintOf(item["balance"], "dunning item balance"),
    dueOn: plainDate(item["dueOn"]),
  });
}

function runCustomersOf(value: unknown): readonly InvoiceDunningRunCustomer[] {
  return recordsOf(value, "invoice dunning run items").map((customer) =>
    compact<InvoiceDunningRunCustomer>({
      partyId: optionalText(customer["partyId"]),
      balance: bigintOf(customer["balance"], "dunning customer balance"),
      fee: bigintOf(customer["fee"], "dunning customer fee"),
      items: recordsOf(customer["items"], "dunning items").map(runItemOf),
    }),
  );
}

function historyOf(value: unknown): readonly InvoiceDunningHistoryEntry[] {
  return recordsOf(value, "invoice dunning history").map((entry) =>
    compact<InvoiceDunningHistoryEntry>({
      kind: entry["kind"] === "handed_over" ? "handed_over" : "reminder",
      level: Number(entry["level"]),
      textKey: optionalText(entry["textKey"]),
      templateKey: optionalText(entry["templateKey"]),
      fee: bigintOf(entry["fee"], "dunning history fee"),
      balance: bigintOf(entry["balance"], "dunning history balance"),
      note: optionalText(entry["note"]),
      runId: optionalText(entry["runId"]),
      at: optionalInstant(entry["at"]),
    }),
  );
}

function levelsOf(value: unknown): readonly InvoiceDunningLevel[] {
  return recordsOf(value, "invoice dunning levels").map((level) => ({
    level: Number(level["level"]),
    daysAfterDue: Number(level["daysAfterDue"]),
    templateKey: textOf(level["templateKey"]),
    ...(optionalText(level["textKey"]) === undefined
      ? {}
      : { textKey: textOf(level["textKey"]) }),
    fee: bigintOf(level["fee"], "invoice dunning fee"),
    final: level["final"] === true,
  }));
}

function partyPaymentOf(value: unknown): PartyPayment {
  const row = recordOf(value, "record_party_payment");
  const currency = textOf(row["currency"]);

  const at = (key: string): Money =>
    moneyOf(row[key], currency, `party payment ${key}`);

  return compact<PartyPayment>({
    partyId: textOf(row["partyId"]),
    amount: at("amount"),
    allocated: at("allocated"),
    credited: at("credited"),
    creditTransactionId: optionalText(row["creditTransactionId"]),
    credit: at("credit"),
  });
}

/** The collections methods of the invoices client. */
export function invoiceCollections<I>(
  call: BlockCall,
  invoice: (
    fn: string,
    args: Readonly<Record<string, unknown>>,
  ) => AsyncResult<I>,
): InvoiceCollections<I> {
  return {
    recordPartyPayment: (organizationId, payment) =>
      call(
        "record_party_payment",
        {
          tenant: organizationId,
          party_id: payment.partyId,
          amount: amountText(payment.amount),
          currency: payment.amount.currency,
          allocations: payment.allocations.map((part) => ({
            invoiceId: part.invoiceId,
            amount: amountText(part.amount),
          })),
          received_on: payment.receivedOn?.toString() ?? null,
          reference: payment.reference,
          method: payment.method ?? null,
          note: payment.note ?? null,
          ...(payment.actor === undefined ? {} : { actor: payment.actor }),
        },
        partyPaymentOf,
      ),
    applyPartyCredit: (partyId, invoiceId, amount, options = {}) =>
      invoice("apply_party_credit", {
        party_id: partyId,
        invoice: invoiceId,
        amount: amountText(amount),
        ...(options.actor === undefined ? {} : { actor: options.actor }),
      }),
    partyCredits: (organizationId, partyId) =>
      call(
        "list_party_credits",
        { tenant: organizationId, party_id: partyId },
        (value) =>
          recordsOf(value, "party credits").map((credit) =>
            moneyOf(credit["amount"], credit["currency"], "party credit"),
          ),
      ),
    dunningLevels: (organizationId) =>
      call("list_invoice_dunning_levels", { tenant: organizationId }, levelsOf),
    setDunningLevels: (organizationId, levels) =>
      call(
        "set_invoice_dunning_levels",
        {
          tenant: organizationId,
          levels: levels.map((level) => ({
            daysAfterDue: level.daysAfterDue,
            templateKey: level.templateKey,
            ...(level.textKey === undefined ? {} : { textKey: level.textKey }),
            fee: (level.fee ?? 0n).toString(),
            final: level.final ?? false,
          })),
        },
        levelsOf,
      ),
    runDunning: (options = {}) =>
      call(
        "run_invoice_dunning",
        {
          tenant: options.organizationId ?? null,
          as_of: options.asOf?.toString() ?? null,
        },
        (value) => Number(value ?? 0),
      ),
    dunningRuns: (organizationId, options = {}) =>
      call(
        "list_invoice_dunning_runs",
        { tenant: organizationId, max: options.limit ?? 50 },
        runsOf,
      ),
    dunningRunItems: (runId) =>
      call("list_invoice_dunning_run_items", { run: runId }, runCustomersOf),
    dunningHistory: (invoiceId) =>
      call("list_invoice_dunning_history", { invoice: invoiceId }, historyOf),
    handOverToCollection: (invoiceIds, agencyPartyId, options = {}) =>
      call(
        "hand_over_to_collection",
        {
          invoice_ids: invoiceIds,
          agency_party_id: agencyPartyId,
          note: options.note ?? null,
        },
        (value) =>
          recordsOf(value, "hand_over_to_collection").map((row) =>
            textOf(row["id"]),
          ),
      ),
    pauseDunning: (invoiceId, until, reason) =>
      invoice("pause_invoice_dunning", {
        invoice: invoiceId,
        until: until === null ? null : until.toString(),
        reason: reason ?? null,
      }),
  };
}
