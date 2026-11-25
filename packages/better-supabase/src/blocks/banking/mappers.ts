import type { FilterQuery } from "../../list/filter-query.ts";
import type {
  BankAccount,
  BankMatch,
  BankMatchReason,
  BankMatchSuggestion,
  BankReconciliation,
  BankRule,
  BankStatement,
  BankStatementImport,
  BankTransaction,
  PaymentBatch,
  PaymentBatchItem,
  SepaExportOptions,
} from "./banking.ts";
import type {
  BankDate,
  BankStatementInput,
  BankTransactionInput,
} from "./statement.ts";

import { optionalPlainDateOf, plainDateOf } from "../../core/block-helpers.ts";
import { dbError } from "../../core/errors.ts";
import { AsyncResult } from "../../core/result.ts";
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
import { sepaCreditTransferXml } from "./sepa.ts";

export const REASONS: readonly BankMatchReason[] = [
  "reference",
  "remittance",
  "amount",
  "counterparty",
];

export const dateText = (value: BankDate | undefined): string | undefined =>
  value === undefined ? undefined : value.toString();

export function accountOf(value: unknown, fn: string): BankAccount {
  const row = recordOf(value, fn);
  const iban = optionalText(row["iban"]);
  const bic = optionalText(row["bic"]);
  const holder = optionalText(row["holder"]);
  const journalId = optionalText(row["journalId"]);
  const archivedAt = optionalInstant(row["archivedAt"]);

  return {
    id: textOf(row["id"]),
    organizationId: textOf(row["organizationId"]),
    name: textOf(row["name"]),
    ...(iban ? { iban } : {}),
    ...(bic ? { bic } : {}),
    currency: textOf(row["currency"]),
    ...(holder ? { holder } : {}),
    primary: row["primary"] === true,
    position: typeof row["position"] === "number" ? row["position"] : 0,
    ...(journalId ? { journalId } : {}),
    ...(archivedAt ? { archivedAt } : {}),
    createdAt: requiredInstant(row["createdAt"], "createdAt"),
    updatedAt: requiredInstant(row["updatedAt"], "updatedAt"),
    fields: isRecord(row["fields"]) ? row["fields"] : {},
  };
}

export function statementOf(value: unknown, fn: string): BankStatement {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const reference = optionalText(row["reference"]);
  const fromOn = optionalPlainDateOf(row["fromOn"]);
  const untilOn = optionalPlainDateOf(row["untilOn"]);

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

export function matchOf(
  value: unknown,
  currency: unknown,
  fn: string,
): BankMatch {
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

export const TRANSACTION_TEXT = [
  "statementId",
  "counterpartyName",
  "counterpartyIban",
  "remittance",
  "structuredReference",
  "endToEndId",
  "ruleId",
  "matchedBy",
] as const;

export function transactionOf(value: unknown, fn: string): BankTransaction {
  const row = recordOf(value, fn);
  const currency = row["currency"];
  const valueOn = optionalPlainDateOf(row["valueOn"]);
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
    bookedOn: plainDateOf(row["bookedOn"]),
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

export const isFilterGroup = (value: unknown): value is FilterQuery =>
  isRecord(value) && value["type"] === "group" && Array.isArray(value["rules"]);

export function ruleOf(value: unknown, fn: string): BankRule {
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

export function suggestionOf(value: unknown, fn: string): BankMatchSuggestion {
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

export function reconciliationOf(
  value: unknown,
  fn: string,
): BankReconciliation {
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
    asOf: plainDateOf(row["asOf"]),
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

export function batchItemOf(
  value: unknown,
  currency: unknown,
): PaymentBatchItem {
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

export function batchOf(value: unknown, fn: string): PaymentBatch {
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
    dueBy: plainDateOf(row["dueBy"]),
    executionOn: plainDateOf(row["executionOn"]),
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

export function importOf(value: unknown, fn: string): BankStatementImport {
  const row = recordOf(value, fn);

  return {
    statement: statementOf(row["statement"], fn),
    imported: Number(row["imported"]),
    skipped: Number(row["skipped"]),
  };
}

export const sepaInvalid = (message: string): AsyncResult<string> =>
  AsyncResult.err(
    dbError("invalid_request", message, { hint: "SEPA_EXPORT_INVALID" }),
  );

/** The SEPA file of a batch, or the error of what the format refuses. */
export function sepaFile(
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
export const defined = (
  value: Record<string, unknown>,
): Record<string, unknown> =>
  Object.fromEntries(
    Object.entries(value).filter(([, entry]) => entry !== undefined),
  );

export const transactionArg = (
  tx: BankTransactionInput,
): Record<string, unknown> =>
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

export const statementArg = (
  statement: BankStatementInput,
): Record<string, unknown> =>
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
