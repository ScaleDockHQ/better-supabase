import type { BlockSqlContext, ExtraColumn } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import { extraFieldsJson, fail, SERVICE_CALLER } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/** What a bank statement was read from. */
export const STATEMENT_FORMATS = ["camt053", "mt940", "csv", "feed"] as const;

/** Where a bank transaction stands. */
export const TRANSACTION_STATUSES = [
  "unmatched",
  "matched",
  "ignored",
] as const;

/** What a bank transaction can be matched to. */
export const MATCH_TARGETS = [
  "invoice",
  "accounting_entry",
  "expense_report",
] as const;

/** The reference prefix of the invoice payment a bank match records. */
export const MATCH_REFERENCE = "bank-match:";

/** The reference prefix of the refund that undoes it on unmatch. */
export const UNMATCH_REFERENCE = "bank-unmatch:";

/** A block the banking functions read, when it's there and managed. */
export function linked(
  ctx: BlockSqlContext,
  module: string,
): BlockSqlContext | undefined {
  return ctx.installed(module) && ctx.of(module).mode !== "custom"
    ? ctx.of(module)
    : undefined;
}

/** The SQL pieces the banking files share. */
export interface BankingSql {
  readonly fn: (name: string) => string;
  /**
   * Columns of bank_accounts, bank_statements, bank_transactions, bank_matches
   * and bank_rules.
   */
  readonly a: (column: string) => string;
  readonly s: (column: string) => string;
  readonly t: (column: string) => string;
  readonly m: (column: string) => string;
  readonly r: (column: string) => string;
  readonly accounts: string;
  readonly statements: string;
  readonly transactions: string;
  readonly matches: string;
  readonly rules: string;
  /** `options.extraColumns` on the bank accounts table. */
  readonly extras: readonly ExtraColumn[];
  readonly read: string;
  readonly import: string;
  readonly reconcile: string;
  readonly manage: string;
  /** The service role, or a member of `tenant` with `permission`. */
  readonly allowed: (tenant: string, permission: string) => string;
  readonly forbidden: (message: string) => string;
  readonly accountInvalid: (message: string) => string;
  readonly statementInvalid: (message: string) => string;
  readonly matchInvalid: (message: string) => string;
  readonly ruleInvalid: (message: string) => string;
  readonly accountMissing: string;
  readonly transactionMissing: string;
  readonly ruleMissing: string;
  /** Refuses a transaction whose status isn't one of `from`. */
  readonly statusInvalid: (row: string, action: string) => string;
  readonly accountJson: (row: string) => string;
  readonly statementJson: (row: string) => string;
  readonly transactionJson: (row: string) => string;
  readonly matchJson: (row: string) => string;
  readonly ruleJson: (row: string) => string;
  /** The JSON a bank rule's conditions match against. */
  readonly conditionPayload: (row: string) => string;
  /** The matches of a transaction, as a JSON array. */
  readonly matchesOf: (row: string) => string;
  /** Records a `bank_transaction.*` event of a bank_transactions row. */
  readonly recordTransaction: (
    type: "bank_transaction.matched" | "bank_transaction.unmatched",
    row: string,
    summary: string,
    extra?: string,
  ) => string;
}

export function bankingSql(ctx: BlockSqlContext): BankingSql {
  const col =
    (table: string) =>
    (column: string): string =>
      ctx.col(table, column);

  const a = col("accounts");
  const s = col("statements");
  const t = col("transactions");
  const m = col("matches");
  const r = col("rules");
  const matches = ctx.table("matches");
  const extras = ctx.extraColumns("accounts", ["fields"]);

  const matchJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${m("id")}, 'transactionId', ${row}.${m("transaction")}, 'targetType', ${row}.${m("targetType")}, 'targetId', ${row}.${m("targetId")}, 'amount', ${row}.${m("amount")}::text, 'createdBy', ${row}.${m("createdBy")}, 'createdAt', ${row}.${m("createdAt")})`;

  const matchesOf = (row: string): string =>
    `coalesce((select jsonb_agg(${matchJson("y")} order by y.${m("createdAt")}, y.${m("id")}) from ${matches} y where y.${m("transaction")} = ${row}.${t("id")}), '[]'::jsonb)`;

  return {
    fn: (name) => ctx.fn(name),
    a,
    s,
    t,
    m,
    r,
    accounts: ctx.table("accounts"),
    statements: ctx.table("statements"),
    transactions: ctx.table("transactions"),
    matches,
    rules: ctx.table("rules"),
    extras,
    read: ctx.permission("read", OPERATIONS["banking.read"]),
    import: ctx.permission("import", OPERATIONS["banking.import"]),
    reconcile: ctx.permission("reconcile", OPERATIONS["banking.reconcile"]),
    manage: ctx.permission("manage", OPERATIONS["banking.manage"]),
    allowed: (tenant, permission) =>
      `(${SERVICE_CALLER} or (${tenant} is not null and ${ctx.can("tenant", tenant, permission)}))`,
    forbidden: (message) => fail("BANKING_FORBIDDEN", message),
    accountInvalid: (message) => fail("BANK_ACCOUNT_INVALID", message, "22023"),
    statementInvalid: (message) =>
      fail("BANK_STATEMENT_INVALID", message, "22023"),
    matchInvalid: (message) =>
      fail("BANK_TRANSACTION_MATCH_INVALID", message, "22023"),
    ruleInvalid: (message) => fail("BANK_RULE_INVALID", message, "22023"),
    accountMissing: fail(
      "BANK_ACCOUNT_NOT_FOUND",
      "no such bank account",
      "P0002",
    ),
    transactionMissing: fail(
      "BANK_TRANSACTION_NOT_FOUND",
      "no such bank transaction",
      "P0002",
    ),
    ruleMissing: fail("BANK_RULE_NOT_FOUND", "no such bank rule", "P0002"),
    statusInvalid: (row, action) =>
      `raise exception 'a % bank transaction can''t be ${action}', ${row}.${t("status")} using errcode = '55000', hint = 'BANK_TRANSACTION_STATUS_INVALID', detail = jsonb_build_object('status', ${row}.${t("status")}, 'action', ${sqlString(action)})::text;`,
    accountJson: (row) =>
      `jsonb_build_object('id', ${row}.${a("id")}, 'organizationId', ${row}.${a("tenant")}, 'name', ${row}.${a("name")}, 'iban', ${row}.${a("iban")}, 'bic', ${row}.${a("bic")}, 'currency', ${row}.${a("currency")}, 'journalId', ${row}.${a("journal")}, 'archivedAt', ${row}.${a("archivedAt")}, 'createdAt', ${row}.${a("createdAt")}, 'updatedAt', ${row}.${a("updatedAt")}${extraFieldsJson(row, extras)})`,
    statementJson: (row) =>
      `jsonb_build_object('id', ${row}.${s("id")}, 'organizationId', ${row}.${s("tenant")}, 'accountId', ${row}.${s("account")}, 'reference', ${row}.${s("reference")}, 'fromOn', ${row}.${s("fromOn")}, 'untilOn', ${row}.${s("untilOn")}, 'openingBalance', ${row}.${s("openingBalance")}::text, 'closingBalance', ${row}.${s("closingBalance")}::text, 'currency', (select z.${a("currency")} from ${ctx.table("accounts")} z where z.${a("id")} = ${row}.${s("account")}), 'format', ${row}.${s("format")}, 'attachmentId', ${row}.${s("attachment")}, 'importedBy', ${row}.${s("importedBy")}, 'createdAt', ${row}.${s("createdAt")})`,
    transactionJson: (row) =>
      `jsonb_build_object('id', ${row}.${t("id")}, 'organizationId', ${row}.${t("tenant")}, 'accountId', ${row}.${t("account")}, 'statementId', ${row}.${t("statement")}, 'bookedOn', ${row}.${t("bookedOn")}, 'valueOn', ${row}.${t("valueOn")}, 'amount', ${row}.${t("amount")}::text, 'currency', ${row}.${t("currency")}, 'counterpartyName', ${row}.${t("counterpartyName")}, 'counterpartyIban', ${row}.${t("counterpartyIban")}, 'remittance', ${row}.${t("remittance")}, 'structuredReference', ${row}.${t("structuredReference")}, 'endToEndId', ${row}.${t("endToEndId")}, 'externalId', ${row}.${t("externalId")}, 'status', ${row}.${t("status")}, 'ruleId', ${row}.${t("rule")}, 'matchedAt', ${row}.${t("matchedAt")}, 'matchedBy', ${row}.${t("matchedBy")}, 'createdAt', ${row}.${t("createdAt")}, 'updatedAt', ${row}.${t("updatedAt")}, 'matches', ${matchesOf(row)})`,
    matchJson,
    ruleJson: (row) =>
      `jsonb_build_object('id', ${row}.${r("id")}, 'organizationId', ${row}.${r("tenant")}, 'name', ${row}.${r("name")}, 'conditions', ${row}.${r("conditions")}, 'accountId', ${row}.${r("account")}, 'partyId', ${row}.${r("party")}, 'dimensions', ${row}.${r("dimensions")}, 'priority', ${row}.${r("priority")}, 'active', ${row}.${r("active")}, 'createdAt', ${row}.${r("createdAt")}, 'updatedAt', ${row}.${r("updatedAt")})`,
    conditionPayload: (row) =>
      `jsonb_build_object('accountId', ${row}.${t("account")}, 'bookedOn', ${row}.${t("bookedOn")}, 'valueOn', ${row}.${t("valueOn")}, 'amount', ${row}.${t("amount")}, 'direction', case when ${row}.${t("amount")} < 0 then 'out' else 'in' end, 'currency', ${row}.${t("currency")}, 'counterpartyName', ${row}.${t("counterpartyName")}, 'counterpartyIban', ${row}.${t("counterpartyIban")}, 'remittance', ${row}.${t("remittance")}, 'structuredReference', ${row}.${t("structuredReference")}, 'endToEndId', ${row}.${t("endToEndId")})`,
    matchesOf,
    recordTransaction: (type, row, summary, extra = "") =>
      ctx.record({
        type,
        payload: `jsonb_build_object('organizationId', ${row}.${t("tenant")}, 'id', ${row}.${t("id")}, 'accountId', ${row}.${t("account")}, 'amount', ${row}.${t("amount")}::text, 'currency', ${row}.${t("currency")}, 'status', ${row}.${t("status")}${extra})`,
        subject: `'bank-transactions/' || ${row}.${t("id")}::text`,
        tenant: `${row}.${t("tenant")}`,
        audit: {
          category: "billing",
          targetType: "bank_transaction",
          recordId: `${row}.${t("id")}::text`,
          targetLabel: `${row}.${t("bookedOn")}::text || ' ' || ${row}.${t("amount")}::text || ' ' || ${row}.${t("currency")}`,
          summary: sqlString(summary),
        },
      }),
  };
}
