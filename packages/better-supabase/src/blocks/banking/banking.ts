import type { Money } from "../../commerce/money.ts";
import type {
  BlockFields,
  ExtraFields,
  FieldsOf,
} from "../../core/block-fields.ts";
import type { BlockHooks } from "../../core/block-hooks.ts";
import type { Logger } from "../../core/logger.ts";
import type { StandardSchemaV1 } from "../../core/standard.ts";
import type { FilterQuery } from "../../list/filter-query.ts";
import type { BlockOptions } from "../shared.ts";
import type { BankFeed } from "./feed.ts";
import type {
  BankDate,
  BankStatementFormat,
  BankStatementInput,
  BankTransactionInput,
} from "./statement.ts";

import { blockFields } from "../../core/block-fields.ts";
import { withBlockHooks } from "../../core/block-hooks.ts";
import { requireTenant } from "../../core/block-tenant.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
import { temporal } from "../../core/temporal-required.ts";
import {
  BATCH_ITEM_STATUSES,
  BATCH_STATUSES,
} from "../../sql/modules/banking-batches.ts";
import {
  MATCH_TARGETS,
  STATEMENT_FORMATS,
  TRANSACTION_STATUSES,
} from "../../sql/modules/banking-sql.ts";
import { amountText, moneyOf, optionalMoneyOf } from "../money-codec.ts";
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
  stringsOf,
  textOf,
} from "../shared.ts";
import { bankFeedOf } from "./feed.ts";
import { sepaCreditTransferXml } from "./sepa.ts";

/** Where a bank transaction stands. */
export type BankTransactionStatus = (typeof TRANSACTION_STATUSES)[number];

/** What a bank transaction is matched to. */
export type BankMatchTarget = (typeof MATCH_TARGETS)[number];

/** A bank account. `F` types the extra columns the `fields` schema describes. */
export interface BankAccount<F extends object = Record<never, never>> {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /** Without spaces, upper case. */
  readonly iban?: string;
  readonly bic?: string;
  readonly currency: string;
  /** The accounting journal (`bank` or `cash`) the account books to. */
  readonly journalId?: string;
  readonly archivedAt?: Temporal.Instant;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
  readonly fields: ExtraFields<F>;
}

export interface BankAccountInput<F extends object = Record<never, never>> {
  readonly name?: string;
  /** Checked against its ISO 13616 check digits. */
  readonly iban?: string | null;
  readonly bic?: string | null;
  /** Required when creating an account. */
  readonly currency?: string;
  readonly journalId?: string | null;
  readonly archived?: boolean;
  /** Values for the extra columns, checked by the `fields` schema. */
  readonly fields?: Partial<F>;
}

export interface BankStatement {
  readonly id: string;
  readonly organizationId: string;
  readonly accountId: string;
  readonly reference?: string;
  readonly fromOn?: Temporal.PlainDate;
  readonly untilOn?: Temporal.PlainDate;
  readonly openingBalance?: Money;
  readonly closingBalance?: Money;
  readonly format: BankStatementFormat;
  readonly attachmentId?: string;
  readonly importedBy?: string;
  readonly createdAt: Temporal.Instant;
}

/** What one import added: a transaction seen before is skipped. */
export interface BankStatementImport {
  readonly statement: BankStatement;
  readonly imported: number;
  readonly skipped: number;
}

export interface BankMatch {
  readonly id: string;
  readonly transactionId: string;
  readonly targetType: BankMatchTarget;
  readonly targetId: string;
  /** Signed like the transaction: the part of it this match covers. */
  readonly amount: Money;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
}

export interface BankTransaction {
  readonly id: string;
  readonly organizationId: string;
  readonly accountId: string;
  readonly statementId?: string;
  readonly bookedOn: Temporal.PlainDate;
  readonly valueOn?: Temporal.PlainDate;
  /** Negative money left the account. */
  readonly amount: Money;
  readonly counterpartyName?: string;
  readonly counterpartyIban?: string;
  readonly remittance?: string;
  readonly structuredReference?: string;
  readonly endToEndId?: string;
  readonly externalId: string;
  readonly status: BankTransactionStatus;
  /** The bank rule that matched or ignored it. */
  readonly ruleId?: string;
  readonly matchedAt?: Temporal.Instant;
  readonly matchedBy?: string;
  readonly matches: readonly BankMatch[];
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface BankTransactionListOptions {
  readonly status?: BankTransactionStatus;
  readonly since?: BankDate;
  readonly until?: BankDate;
  /** Default 100, at most 500. */
  readonly limit?: number;
  readonly offset?: number;
}

/** Why a suggestion scored: each reason adds to `score`. */
export type BankMatchReason =
  | "reference"
  | "remittance"
  | "amount"
  | "counterparty";

/** An open invoice that may be what a transaction pays. */
export interface BankMatchSuggestion {
  readonly targetType: BankMatchTarget;
  readonly targetId: string;
  readonly label: string;
  /** What is still open on the invoice. */
  readonly balance: Money;
  readonly score: number;
  readonly reasons: readonly BankMatchReason[];
}

export interface BankMatchInput {
  readonly targetType: BankMatchTarget;
  readonly targetId: string;
  /**
   * Signed like the transaction. Default: the whole transaction; the matches
   * add up to the transaction's amount.
   */
  readonly amount?: Money;
}

export interface BankRule {
  readonly id: string;
  readonly organizationId: string;
  readonly name: string;
  /**
   * A filter tree over `{ accountId, bookedOn, valueOn, amount, direction ("in"
   * or "out"), currency, counterpartyName, counterpartyIban, remittance,
   * structuredReference, endToEndId }`.
   */
  readonly conditions: FilterQuery;
  /**
   * The ledger account a match books the other side to; a rule without one
   * ignores what it matches.
   */
  readonly accountId?: string;
  readonly partyId?: string;
  readonly dimensions: Readonly<Record<string, string>>;
  /** Lower runs first. */
  readonly priority: number;
  readonly active: boolean;
  readonly createdAt: Temporal.Instant;
  readonly updatedAt: Temporal.Instant;
}

export interface BankRuleInput {
  readonly name?: string;
  readonly conditions?: FilterQuery;
  readonly accountId?: string | null;
  readonly partyId?: string | null;
  readonly dimensions?: Readonly<Record<string, string>>;
  readonly priority?: number;
  readonly active?: boolean;
}

export interface BankRuleRun {
  readonly matched: number;
  readonly ignored: number;
}

/** Where a bank account stands on a day. */
export interface BankReconciliation {
  readonly accountId: string;
  readonly asOf: Temporal.PlainDate;
  /** The last statement with a closing balance up to `asOf`. */
  readonly statementId?: string;
  readonly statementBalance?: Money;
  /** The sum of the imported transactions up to `asOf`. */
  readonly transactionTotal: Money;
  readonly unmatchedCount: number;
  readonly unmatchedTotal: Money;
  /** The balance of the account's ledger account, with accounting. */
  readonly ledgerBalance?: Money;
  /** The statement balance less the ledger balance. */
  readonly difference?: Money;
  /** Nothing unmatched and the statement agrees with the books. */
  readonly reconciled: boolean;
}

/** Where a payment batch stands. */
export type PaymentBatchStatus = (typeof BATCH_STATUSES)[number];

/** Where one payment of a batch stands. */
export type PaymentBatchItemStatus = (typeof BATCH_ITEM_STATUSES)[number];

/** One supplier bill a payment batch pays. */
export interface PaymentBatchItem {
  readonly id: string;
  readonly invoiceId: string;
  readonly partyId: string;
  readonly creditorName: string;
  readonly creditorIban: string;
  readonly creditorBic?: string;
  /** What is paid for the bill: its balance less the discount taken. */
  readonly amount: Money;
  /** The early payment discount the payment takes. */
  readonly discount: Money;
  readonly endToEndId: string;
  readonly remittance?: string;
  readonly status: PaymentBatchItemStatus;
}

/**
 * A batch of supplier bills paid from one bank account. It is a draft until
 * `postPaymentBatch`, posted (paid, pending the bank) until its bank
 * transaction is matched, then reconciled.
 */
export interface PaymentBatch {
  readonly id: string;
  readonly organizationId: string;
  readonly accountId: string;
  readonly reference: string;
  /** The SEPA MsgId of the file. */
  readonly messageId: string;
  readonly dueBy: Temporal.PlainDate;
  readonly executionOn: Temporal.PlainDate;
  readonly total: Money;
  readonly itemCount: number;
  readonly status: PaymentBatchStatus;
  /** The bank transaction that reconciled it. */
  readonly transactionId?: string;
  readonly createdBy?: string;
  readonly createdAt: Temporal.Instant;
  readonly postedAt?: Temporal.Instant;
  readonly reconciledAt?: Temporal.Instant;
  readonly items: readonly PaymentBatchItem[];
}

/** The bank details of a supplier a batch pays. */
export interface PaymentBatchCreditor {
  readonly name: string;
  readonly iban: string;
  readonly bic?: string;
}

/** What `createPaymentBatch` selects and who it pays. */
export interface PaymentBatchInput {
  readonly accountId: string;
  /** Bills due by this day, or whose early payment discount ends by it. */
  readonly dueBy: BankDate;
  /** The day the bank executes the payments. Default: today. */
  readonly executionOn?: BankDate;
  readonly reference?: string;
  /** Pay only these bills; one that needs approval refuses the batch. */
  readonly invoiceIds?: readonly string[];
  /** The bank details per supplier (the party id of the bill). */
  readonly creditors: Readonly<Record<string, PaymentBatchCreditor>>;
}

/** The parties of a SEPA file that the batch doesn't hold. */
export interface SepaExportOptions {
  /** The account holder's name. Default: the bank account's name. */
  readonly debtorName?: string;
  /** The initiating party. Default: the debtor. */
  readonly initiatingPartyName?: string;
}

export interface BankFeedSync {
  /** The provider's account id. */
  readonly accountRef: string;
  /** Read the transactions booked on or after this day. */
  readonly since: BankDate;
}

export interface Banking<F extends object = Record<never, never>> {
  saveAccount(input: {
    input: BankAccountInput<F>;
    accountId?: string | undefined;
  }): AsyncResult<BankAccount<F>>;
  accounts(options?: {
    readonly includeArchived?: boolean;
  }): AsyncResult<readonly BankAccount<F>[]>;
  /**
   * Imports a statement, a parsed file or a feed page. A transaction whose
   * `externalId` the account has seen is skipped, so importing twice adds
   * nothing.
   */
  importStatement(input: {
    accountId: string;
    statement: BankStatementInput;
  }): AsyncResult<BankStatementImport>;
  statements(accountId: string): AsyncResult<readonly BankStatement[]>;
  transactions(
    input: { accountId: string } & BankTransactionListOptions,
  ): AsyncResult<readonly BankTransaction[]>;
  getTransaction(
    transactionId: string,
  ): AsyncResult<BankTransaction | undefined>;
  /**
   * Open invoices the transaction may pay, best first: by structured reference
   * (ISO 11649 or a Dutch betalingskenmerk), the invoice number in the
   * remittance, the open amount and the counterparty's IBAN.
   */
  suggestMatches(
    transactionId: string,
  ): AsyncResult<readonly BankMatchSuggestion[]>;
  /**
   * Matches the transaction to invoices, posted journal entries or expense
   * reports. An invoice match records an invoice payment. The amounts add up to
   * the transaction's, or it fails with `BANK_TRANSACTION_MATCH_INVALID`.
   */
  match(input: {
    transactionId: string;
    matches: readonly BankMatchInput[];
  }): AsyncResult<BankTransaction>;
  /** Undoes the matches: invoice payments are refunded, a rule's entry reversed. */
  unmatch(transactionId: string): AsyncResult<BankTransaction>;
  /** `false` puts an ignored transaction back as unmatched. */
  ignore(input: {
    transactionId: string;
    ignored?: boolean | undefined;
  }): AsyncResult<BankTransaction>;
  saveRule(input: {
    input: BankRuleInput;
    ruleId?: string | undefined;
  }): AsyncResult<BankRule>;
  rules(): AsyncResult<readonly BankRule[]>;
  deleteRule(ruleId: string): AsyncResult<void>;
  /** Runs the active rules over the account's unmatched transactions. */
  applyRules(accountId: string): AsyncResult<BankRuleRun>;
  reconciliation(input: {
    accountId: string;
    asOf?: BankDate | undefined;
  }): AsyncResult<BankReconciliation>;
  /**
   * Selects the approved open supplier bills due by a date into a draft payment
   * batch of one bank account. A bill whose early payment discount is still
   * open on the execution day is paid less the discount. Fails with
   * `PAYMENT_BATCH_EMPTY` when nothing qualifies and with
   * `PAYMENT_BATCH_CREDITOR_MISSING` for a supplier without bank details.
   */
  createPaymentBatch(input: PaymentBatchInput): AsyncResult<PaymentBatch>;
  paymentBatches(options?: {
    readonly status?: PaymentBatchStatus;
    readonly limit?: number;
  }): AsyncResult<readonly PaymentBatch[]>;
  getPaymentBatch(batchId: string): AsyncResult<PaymentBatch>;
  /**
   * Posts a draft batch: its bills count as paid, pending the bank. Matching
   * the bank transaction with a `payment_batch` target records the payments.
   * Fails with `PAYMENT_BATCH_APPROVAL_REQUIRED` for a bill still waiting for
   * approval.
   */
  postPaymentBatch(batchId: string): AsyncResult<PaymentBatch>;
  /** Cancels a draft or posted batch and frees its bills. */
  cancelPaymentBatch(batchId: string): AsyncResult<PaymentBatch>;
  /**
   * The batch as a SEPA credit transfer file (ISO 20022 pain.001.001.09),
   * written from the bank account's name, IBAN and BIC. Only euro batches.
   */
  exportSepaCreditTransfer(
    input: { batchId: string } & SepaExportOptions,
  ): AsyncResult<string>;
  /** Reads a bank feed's transactions since a day and imports them. */
  syncFeed(input: {
    accountId: string;
    feed: BankFeed;
    sync: BankFeedSync;
  }): AsyncResult<BankStatementImport>;
}

export interface BankingOptions<
  S extends StandardSchemaV1 | undefined = undefined,
> extends BlockOptions {
  /**
   * A Standard Schema for the bank accounts' extra columns
   * (`blocks.banking.options.extraColumns`), keyed by database name.
   */
  readonly fields?: S;
  readonly hooks?: NoInfer<BlockHooks<Banking<FieldsOf<S>>>>;
  /** Receives the errors `after` hooks throw. Default: `console`. */
  readonly logger?: Logger;
}

const REASONS: readonly BankMatchReason[] = [
  "reference",
  "remittance",
  "amount",
  "counterparty",
];

const dateText = (value: BankDate | undefined): string | undefined =>
  value === undefined ? undefined : value.toString();

const plainDate = (value: unknown): Temporal.PlainDate =>
  temporal().PlainDate.from(textOf(value));

const optionalDate = (value: unknown): Temporal.PlainDate | undefined =>
  typeof value === "string" && value !== "" ? plainDate(value) : undefined;

function accountOf(value: unknown, fn: string): BankAccount {
  const row = recordOf(value, fn);
  const iban = optionalText(row["iban"]);
  const bic = optionalText(row["bic"]);
  const journalId = optionalText(row["journalId"]);
  const archivedAt = optionalInstant(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    ...(iban ? { iban } : {}),
    ...(bic ? { bic } : {}),
    currency: textOf(row["currency"]),
    ...(journalId ? { journalId } : {}),
    ...(archivedAt ? { archivedAt } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

function statementOf(value: unknown, fn: string): BankStatement {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const reference = optionalText(row["reference"]);
  const fromOn = optionalDate(row["fromOn"]);
  const untilOn = optionalDate(row["untilOn"]);

  const openingBalance = optionalMoneyOf(
    row["openingBalance"],
    currency,
    "openingBalance",
  );

  const closingBalance = optionalMoneyOf(
    row["closingBalance"],
    currency,
    "closingBalance",
  );

  const attachmentId = optionalText(row["attachmentId"]);
  const importedBy = optionalText(row["importedBy"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    accountId: textOf(row["accountId"]),
    ...(reference ? { reference } : {}),
    ...(fromOn ? { fromOn } : {}),
    ...(untilOn ? { untilOn } : {}),
    ...(openingBalance ? { openingBalance } : {}),
    ...(closingBalance ? { closingBalance } : {}),
    format: enumOrThrow(
      row["format"],
      STATEMENT_FORMATS,
      "bank statement format",
    ),
    ...(attachmentId ? { attachmentId } : {}),
    ...(importedBy ? { importedBy } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

function matchOf(value: unknown, currency: unknown, fn: string): BankMatch {
  const row = recordOf(value, fn);
  const createdBy = optionalText(row["createdBy"]);

  return {
    id: textOf(row["id"]),
    transactionId: textOf(row["transactionId"]),
    targetType: enumOrThrow(
      row["targetType"],
      MATCH_TARGETS,
      "bank match target",
    ),
    targetId: textOf(row["targetId"]),
    amount: moneyOf(row["amount"], currency),
    ...(createdBy ? { createdBy } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
  };
}

const TRANSACTION_TEXT = [
  "statementId",
  "counterpartyName",
  "counterpartyIban",
  "remittance",
  "structuredReference",
  "endToEndId",
  "ruleId",
  "matchedBy",
] as const;

function transactionOf(value: unknown, fn: string): BankTransaction {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const valueOn = optionalDate(row["valueOn"]);
  const matchedAt = optionalInstant(row["matchedAt"]);

  const text = Object.fromEntries(
    TRANSACTION_TEXT.flatMap((key) => {
      const found = optionalText(row[key]);

      return found ? [[key, found]] : [];
    }),
  );

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    accountId: textOf(row["accountId"]),
    bookedOn: plainDate(row["bookedOn"]),
    ...(valueOn ? { valueOn } : {}),
    amount: moneyOf(row["amount"], currency),
    ...text,
    externalId: textOf(row["externalId"]),
    status: enumOrThrow(
      row["status"],
      TRANSACTION_STATUSES,
      "bank transaction status",
    ),
    ...(matchedAt ? { matchedAt } : {}),
    matches: recordsOf(row["matches"], fn).map((match) =>
      matchOf(match, currency, fn),
    ),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

const isFilterGroup = (value: unknown): value is FilterQuery =>
  isRecord(value) && value["type"] === "group" && Array.isArray(value["rules"]);

function ruleOf(value: unknown, fn: string): BankRule {
  const row = recordOf(value, fn);
  const conditions = row["conditions"];
  const dimensions = row["dimensions"];
  const accountId = optionalText(row["accountId"]);
  const partyId = optionalText(row["partyId"]);

  if (!isFilterGroup(conditions)) {
    throw new TypeError(
      `bank rule conditions are ${JSON.stringify(conditions)}`,
    );
  }

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    conditions,
    ...(accountId ? { accountId } : {}),
    ...(partyId ? { partyId } : {}),
    dimensions: isRecord(dimensions)
      ? Object.fromEntries(
          Object.entries(dimensions).map(([key, entry]) => [
            key,
            String(entry),
          ]),
        )
      : {},
    priority: Number(row["priority"]),
    active: row["active"] === true,
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
  };
}

function suggestionOf(value: unknown, fn: string): BankMatchSuggestion {
  const row = recordOf(value, fn);

  return {
    targetType: enumOrThrow(
      row["targetType"],
      MATCH_TARGETS,
      "bank match target",
    ),
    targetId: textOf(row["targetId"]),
    label: textOf(row["label"]),
    balance: moneyOf(row["balance"], row["currency"], "balance"),
    score: Number(row["score"]),
    reasons: stringsOf(row["reasons"]).map((reason) =>
      enumOrThrow(reason, REASONS, "bank match reason"),
    ),
  };
}

function reconciliationOf(value: unknown, fn: string): BankReconciliation {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const statementId = optionalText(row["statementId"]);

  const statementBalance = optionalMoneyOf(
    row["statementBalance"],
    currency,
    "statementBalance",
  );

  const ledgerBalance = optionalMoneyOf(
    row["ledgerBalance"],
    currency,
    "ledgerBalance",
  );

  const difference = optionalMoneyOf(row["difference"], currency, "difference");

  return {
    accountId: textOf(row["accountId"]),
    asOf: plainDate(row["asOf"]),
    ...(statementId ? { statementId } : {}),
    ...(statementBalance ? { statementBalance } : {}),
    transactionTotal: moneyOf(
      row["transactionTotal"],
      currency,
      "transactionTotal",
    ),
    unmatchedCount: Number(row["unmatchedCount"]),
    unmatchedTotal: moneyOf(row["unmatchedTotal"], currency, "unmatchedTotal"),
    ...(ledgerBalance ? { ledgerBalance } : {}),
    ...(difference ? { difference } : {}),
    reconciled: row["reconciled"] === true,
  };
}

function batchItemOf(value: unknown, currency: unknown): PaymentBatchItem {
  const row = recordOf(value, "payment batch item");
  const bic = optionalText(row["creditorBic"]);
  const remittance = optionalText(row["remittance"]);

  return {
    id: textOf(row["id"]),
    invoiceId: textOf(row["invoiceId"]),
    partyId: textOf(row["partyId"]),
    creditorName: textOf(row["creditorName"]),
    creditorIban: textOf(row["creditorIban"]),
    ...(bic ? { creditorBic: bic } : {}),
    amount: moneyOf(row["amount"], currency),
    discount: moneyOf(row["discount"], currency, "discount"),
    endToEndId: textOf(row["endToEndId"]),
    ...(remittance ? { remittance } : {}),
    status: enumOrThrow(
      row["status"],
      BATCH_ITEM_STATUSES,
      "payment batch item status",
    ),
  };
}

function batchOf(value: unknown, fn: string): PaymentBatch {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const transactionId = optionalText(row["transactionId"]);
  const createdBy = optionalText(row["createdBy"]);
  const postedAt = optionalInstant(row["postedAt"]);
  const reconciledAt = optionalInstant(row["reconciledAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    accountId: textOf(row["accountId"]),
    reference: textOf(row["reference"]),
    messageId: textOf(row["messageId"]),
    dueBy: plainDate(row["dueBy"]),
    executionOn: plainDate(row["executionOn"]),
    total: moneyOf(row["total"], currency, "total"),
    itemCount: Number(row["itemCount"]),
    status: enumOrThrow(row["status"], BATCH_STATUSES, "payment batch status"),
    ...(transactionId ? { transactionId } : {}),
    ...(createdBy ? { createdBy } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    ...(postedAt ? { postedAt } : {}),
    ...(reconciledAt ? { reconciledAt } : {}),
    items: recordsOf(row["items"], fn).map((item) =>
      batchItemOf(item, currency),
    ),
  };
}

function importOf(value: unknown, fn: string): BankStatementImport {
  const row = recordOf(value, fn);

  return {
    statement: statementOf(row["statement"], fn),
    imported: Number(row["imported"]),
    skipped: Number(row["skipped"]),
  };
}

const sepaInvalid = (message: string): AsyncResult<string> =>
  AsyncResult.err(
    dbError("invalid_request", message, { hint: "SEPA_EXPORT_INVALID" }),
  );

/** The SEPA file of a batch, or the error of what the format refuses. */
function sepaFile(
  batch: PaymentBatch,
  accounts: readonly BankAccount[],
  options: SepaExportOptions,
): AsyncResult<string> {
  const account = accounts.find((each) => each.id === batch.accountId);

  if (!account?.iban) {
    return sepaInvalid("The batch's bank account has no IBAN");
  }

  try {
    return AsyncResult.ok(
      sepaCreditTransferXml({
        messageId: batch.messageId,
        createdAt: batch.createdAt,
        executionOn: batch.executionOn,
        debtorName: options.debtorName ?? account.name,
        debtorIban: account.iban,
        ...(account.bic ? { debtorBic: account.bic } : {}),
        ...(options.initiatingPartyName
          ? { initiatingPartyName: options.initiatingPartyName }
          : {}),
        transfers: batch.items
          .filter((item) => item.status !== "cancelled")
          .map((item) => ({
            endToEndId: item.endToEndId,
            amount: item.amount,
            creditorName: item.creditorName,
            creditorIban: item.creditorIban,
            ...(item.creditorBic ? { creditorBic: item.creditorBic } : {}),
            ...(item.remittance ? { remittance: item.remittance } : {}),
          })),
      }),
    );
  } catch (error) {
    return sepaInvalid(error instanceof Error ? error.message : String(error));
  }
}

/** Drops `undefined` so the SQL reads a missing key, not `null`. */
const defined = (value: Record<string, unknown>): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

const transactionArg = (tx: BankTransactionInput): Record<string, unknown> =>
  defined({
    externalId: tx.externalId,
    bookedOn: dateText(tx.bookedOn),
    valueOn: dateText(tx.valueOn),
    amount: amountText(tx.amount),
    currency: tx.amount.currency,
    counterpartyName: tx.counterpartyName,
    counterpartyIban: tx.counterpartyIban,
    remittance: tx.remittance,
    structuredReference: tx.structuredReference,
    endToEndId: tx.endToEndId,
  });

const statementArg = (statement: BankStatementInput): Record<string, unknown> =>
  defined({
    reference: statement.reference,
    fromOn: dateText(statement.fromOn),
    untilOn: dateText(statement.untilOn),
    openingBalance:
      statement.openingBalance === undefined
        ? undefined
        : amountText(statement.openingBalance),
    closingBalance:
      statement.closingBalance === undefined
        ? undefined
        : amountText(statement.closingBalance),
    format: statement.format,
    attachmentId: statement.attachmentId,
    transactions: statement.transactions.map(transactionArg),
  });

/**
 * Bank accounts, imported statements and their reconciliation against invoices,
 * journal entries and expense reports. Reads through the banking block's
 * functions.
 */
export function createBanking<
  S extends StandardSchemaV1 | undefined = undefined,
>(options: BankingOptions<S>): Banking<FieldsOf<S>> {
  type F = FieldsOf<S>;

  applyTemporal(options);
  const call = blockCall(options.transport, options.schema, options.mappers);
  const tenant = (): AsyncResult<string> => requireTenant(options.tenant);

  const transaction = (fn: string) => (value: unknown) =>
    transactionOf(value, fn);

  const fields: BlockFields<F> = blockFields(
    options.fields,
    "bank account fields",
  );

  const client: Banking<F> = {
    saveAccount: ({ input: { fields: extra, ...input }, accountId }) =>
      tenant().andThen((organizationId) =>
        fields
          .args(extra)
          .andThen((checked) =>
            call(
              "save_bank_account",
              {
                tenant: organizationId,
                input: defined({ ...input, fields: checked }),
                account_id: accountId ?? null,
              },
              (value) => accountOf(value, "save_bank_account"),
            ).andThen(fields.row),
          ),
      ),
    accounts: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_bank_accounts",
          {
            tenant: organizationId,
            include_archived: list.includeArchived ?? false,
          },
          (value) =>
            recordsOf(value, "list_bank_accounts").map((row) =>
              accountOf(row, "list_bank_accounts"),
            ),
        ).andThen(fields.rows),
      ),
    importStatement: ({ accountId, statement }) =>
      call(
        "import_bank_statement",
        { account_id: accountId, statement: statementArg(statement) },
        (value) => importOf(value, "import_bank_statement"),
      ),
    statements: (accountId) =>
      call("list_bank_statements", { account_id: accountId }, (value) =>
        recordsOf(value, "list_bank_statements").map((row) =>
          statementOf(row, "list_bank_statements"),
        ),
      ),
    transactions: ({ accountId, ...list }) =>
      call(
        "list_bank_transactions",
        {
          account_id: accountId,
          filter: defined({
            status: list.status,
            since: dateText(list.since),
            until: dateText(list.until),
            limit: list.limit,
            offset: list.offset,
          }),
        },
        (value) =>
          recordsOf(value, "list_bank_transactions").map((row) =>
            transactionOf(row, "list_bank_transactions"),
          ),
      ),
    getTransaction: (transactionId) =>
      call(
        "get_bank_transaction",
        { transaction_id: transactionId },
        (value) =>
          value === null
            ? undefined
            : transactionOf(value, "get_bank_transaction"),
      ),
    suggestMatches: (transactionId) =>
      call("suggest_bank_matches", { transaction_id: transactionId }, (value) =>
        recordsOf(value, "suggest_bank_matches").map((row) =>
          suggestionOf(row, "suggest_bank_matches"),
        ),
      ),
    match: ({ transactionId, matches }) =>
      call(
        "match_bank_transaction",
        {
          transaction_id: transactionId,
          matches: matches.map((item) =>
            defined({
              targetType: item.targetType,
              targetId: item.targetId,
              amount:
                item.amount === undefined ? undefined : amountText(item.amount),
            }),
          ),
        },
        transaction("match_bank_transaction"),
      ),
    unmatch: (transactionId) =>
      call(
        "unmatch_bank_transaction",
        { transaction_id: transactionId },
        transaction("unmatch_bank_transaction"),
      ),
    ignore: ({ transactionId, ignored = true }) =>
      call(
        "ignore_bank_transaction",
        { transaction_id: transactionId, ignored },
        transaction("ignore_bank_transaction"),
      ),
    saveRule: ({ input, ruleId }) =>
      tenant().andThen((organizationId) =>
        call(
          "save_bank_rule",
          {
            tenant: organizationId,
            input: defined({ ...input }),
            rule_id: ruleId ?? null,
          },
          (value) => ruleOf(value, "save_bank_rule"),
        ),
      ),
    rules: () =>
      tenant().andThen((organizationId) =>
        call("list_bank_rules", { tenant: organizationId }, (value) =>
          recordsOf(value, "list_bank_rules").map((row) =>
            ruleOf(row, "list_bank_rules"),
          ),
        ),
      ),
    deleteRule: (ruleId) =>
      call("delete_bank_rule", { rule_id: ruleId }, () => undefined),
    applyRules: (accountId) =>
      call("apply_bank_rules", { account_id: accountId }, (value) => {
        const row = recordOf(value, "apply_bank_rules");

        return {
          matched: Number(row["matched"]),
          ignored: Number(row["ignored"]),
        };
      }),
    reconciliation: ({ accountId, asOf }) =>
      call(
        "bank_reconciliation_status",
        { account_id: accountId, as_of: dateText(asOf) ?? null },
        (value) => reconciliationOf(value, "bank_reconciliation_status"),
      ),
    createPaymentBatch: (input) =>
      tenant().andThen((organizationId) =>
        call(
          "create_payment_batch",
          {
            tenant: organizationId,
            input: defined({
              accountId: input.accountId,
              dueBy: dateText(input.dueBy),
              executionOn: dateText(input.executionOn),
              reference: input.reference,
              invoiceIds: input.invoiceIds,
              creditors: input.creditors,
            }),
          },
          (value) => batchOf(value, "create_payment_batch"),
        ),
      ),
    paymentBatches: (list = {}) =>
      tenant().andThen((organizationId) =>
        call(
          "list_payment_batches",
          {
            tenant: organizationId,
            status: list.status ?? null,
            page_size: list.limit ?? null,
          },
          (value) =>
            recordsOf(value, "list_payment_batches").map((row) =>
              batchOf(row, "list_payment_batches"),
            ),
        ),
      ),
    getPaymentBatch: (batchId) =>
      call("get_payment_batch", { batch_id: batchId }, (value) =>
        batchOf(value, "get_payment_batch"),
      ),
    postPaymentBatch: (batchId) =>
      call("post_payment_batch", { batch_id: batchId }, (value) =>
        batchOf(value, "post_payment_batch"),
      ),
    cancelPaymentBatch: (batchId) =>
      call("cancel_payment_batch", { batch_id: batchId }, (value) =>
        batchOf(value, "cancel_payment_batch"),
      ),
    exportSepaCreditTransfer: ({ batchId, ...sepa }) =>
      client
        .getPaymentBatch(batchId)
        .andThen((batch) =>
          client
            .accounts({ includeArchived: true })
            .andThen((accounts) => sepaFile(batch, accounts, sepa)),
        ),
    syncFeed: ({ accountId, feed, sync }) =>
      AsyncResult.ok(bankFeedOf(feed))
        .andThen((checked) => checked.transactions(sync.accountRef, sync.since))
        .andThen((transactions) =>
          client.importStatement({
            accountId,
            statement: {
              reference: `${feed.name}:${sync.accountRef}:${String(sync.since)}`,
              fromOn: sync.since,
              format: "feed",
              transactions,
            },
          }),
        ),
  };

  return withBlockHooks(client, options.hooks, {
    block: "banking",
    ...(options.logger ? { logger: options.logger } : {}),
  });
}
