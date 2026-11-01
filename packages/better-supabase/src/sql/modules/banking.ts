import type { BankingEvents } from "../../blocks/banking/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import {
  accountingContributions,
  accountingSourcesSql,
} from "../accounting-sources-sql.ts";
import { schemaPreamble } from "../shared.ts";
import { bankingAccountingSources } from "./banking-accounting.ts";
import {
  BATCH_ITEMS_TABLE,
  BATCHES_TABLE,
  batchContract,
  batchFunctions,
  batchTablesSql,
} from "./banking-batches.ts";
import { bankingFunctions } from "./banking-functions.ts";
import { bankingMatching } from "./banking-matching.ts";
import { BANK_READS, bankingReads } from "./banking-reads.ts";
import { linked } from "./banking-sql.ts";
import { bankingTables } from "./banking-tables.ts";

const TRANSACTION = [
  "organizationId",
  "id",
  "accountId",
  "amount",
  "currency",
  "status",
] as const;

const EVENTS: BlockSqlEvents<BankingEvents> = {
  "bank_statement.imported": {
    subject: "bank-statements",
    payload: ["organizationId", "id", "accountId", "reference", "imported"],
  },
  "bank_transaction.matched": {
    subject: "bank-transactions",
    payload: [...TRANSACTION, "matches", "ruleId"],
  },
  "bank_transaction.unmatched": {
    subject: "bank-transactions",
    payload: TRANSACTION,
  },
};

const NAMES: BlockSqlNames = {
  reads: BANK_READS,
  entities: {
    bank_transaction: {
      table: "transactions",
      singular: "bank_transaction",
      primary: true,
    },
    bank_account: {
      table: "accounts",
      singular: "bank_account",
      subject: {
        title: "name",
        deletedAt: "archivedAt",
        permissions: { read: "read", write: "manage" },
      },
    },
    bank_statement: { table: "statements", singular: "bank_statement" },
    bank_match: { table: "matches", singular: "bank_match" },
    bank_rule: { table: "rules", singular: "bank_rule" },
  },
  events: EVENTS,
  hooks: [
    "after_bank_statement_import",
    "before_bank_transaction_match",
    "after_bank_transaction_match",
  ],
  options: ["extraColumns"],
  tables: {
    accounts: {
      name: "bank_accounts",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        iban: "iban",
        bic: "bic",
        currency: "currency",
        journal: "journal_id",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    rules: {
      name: "bank_rules",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        conditions: "conditions",
        account: "account_id",
        party: "party_id",
        dimensions: "dimensions",
        priority: "priority",
        active: "active",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    statements: {
      name: "bank_statements",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        account: "account_id",
        reference: "reference",
        fromOn: "from_on",
        untilOn: "until_on",
        openingBalance: "opening_balance",
        closingBalance: "closing_balance",
        format: "format",
        attachment: "attachment_id",
        importedBy: "imported_by",
        createdAt: "created_at",
      },
    },
    transactions: {
      name: "bank_transactions",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        account: "account_id",
        statement: "statement_id",
        bookedOn: "booked_on",
        valueOn: "value_on",
        amount: "amount",
        currency: "currency",
        counterpartyName: "counterparty_name",
        counterpartyIban: "counterparty_iban",
        remittance: "remittance",
        structuredReference: "structured_reference",
        endToEndId: "end_to_end_id",
        externalId: "external_id",
        status: "status",
        rule: "rule_id",
        matchedAt: "matched_at",
        matchedBy: "matched_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    matches: {
      name: "bank_matches",
      app: {},
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        transaction: "transaction_id",
        targetType: "target_type",
        targetId: "target_id",
        amount: "amount",
        createdBy: "created_by",
        createdAt: "created_at",
      },
    },
    batches: BATCHES_TABLE,
    batchItems: BATCH_ITEMS_TABLE,
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  return `${schemaPreamble(ctx)}
-- Banking per organization: bank accounts, imported statements and their
-- transactions, matches to invoices, expense reports and accounting entries,
-- bank rules that book or set aside what they match, and reconciliation.
${bankingTables(ctx)}
${batchTablesSql(ctx)}
${bankingFunctions(ctx)}
${batchFunctions(ctx)}
${bankingMatching(ctx)}
${bankingReads(ctx)}
${linked(ctx, "accounting") ? accountingSourcesSql(ctx, bankingAccountingSources(ctx)) : ""}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  return [
    {
      name: "save_bank_account",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "list_bank_accounts", args: ["{id}", "boolean"], returns: "jsonb" },
    {
      name: "import_bank_statement",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "list_bank_statements", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_bank_transactions",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "get_bank_transaction", args: ["uuid"], returns: "jsonb" },
    { name: "suggest_bank_matches", args: ["uuid"], returns: "jsonb" },
    {
      name: "match_bank_transaction",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    { name: "unmatch_bank_transaction", args: ["uuid"], returns: "jsonb" },
    {
      name: "ignore_bank_transaction",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_bank_rule",
      args: ["{id}", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "list_bank_rules", args: ["{id}"], returns: "jsonb" },
    { name: "delete_bank_rule", args: ["uuid"], returns: "void" },
    { name: "apply_bank_rules", args: ["uuid"], returns: "jsonb" },
    {
      name: "bank_reconciliation_status",
      args: ["uuid", "date"],
      returns: "jsonb",
    },
    {
      name: "bank_reconciliation_board",
      args: ["uuid", "integer"],
      returns: "jsonb",
    },
    ...batchContract(ctx),
  ];
}

const CONTRIBUTES: BlockContributes = {
  accounting: (own) =>
    linked(own, "accounting")
      ? accountingContributions(own, bankingAccountingSources(own))
      : [],
};

export const BANKING: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "banking",
  scopes: ["tenant"],
  title: "Banking",
  description:
    "Bank accounts with imported CAMT.053, MT940 and feed statements, matches of each transaction to invoices, expense reports and accounting entries with suggestions from RF and Dutch payment references, bank rules that book or set aside what they match, and a reconciliation status per account against the ledger.",
  requires: ["memberships", "permissions"],
  integrates: [
    "accounting",
    "invoices",
    "expenses",
    "attachments",
    "outbox",
    "audit",
  ],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
};
