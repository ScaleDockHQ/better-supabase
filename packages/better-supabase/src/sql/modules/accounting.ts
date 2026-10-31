import type { AccountingEvents } from "../../blocks/accounting/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { extraFieldsArg, schemaPreamble } from "../shared.ts";
import { accountingBudgets } from "./accounting-budgets.ts";
import {
  accountingCloseFunctions,
  accountingReportFunctions,
} from "./accounting-close.ts";
import { seedDisposalAccounts } from "./accounting-data.ts";
import { accountingEntryFunctions } from "./accounting-entries.ts";
import {
  accountingImportFunctions,
  accountingImportTargets,
  accountingLedgerReports,
  accountingOpeningFunctions,
} from "./accounting-ledger.ts";
import {
  accountingPostingFunctions,
  accountingTaxReport,
} from "./accounting-postings.ts";
import { accountingSetupFunctions } from "./accounting-setup.ts";
import { accountingConfig, ENTRY_RESERVED } from "./accounting-shared.ts";
import { accountingTables } from "./accounting-tables.ts";

const EVENTS: BlockSqlEvents<AccountingEvents> = {
  "accounting_entry.posted": {
    subject: "accounting-entries",
    payload: [
      "organizationId",
      "id",
      "journalId",
      "number",
      "entryDate",
      "sourceType",
      "sourceId",
      "reversesId",
      "total",
    ],
  },
  "accounting_entry.reversed": {
    subject: "accounting-entries",
    payload: [
      "organizationId",
      "id",
      "journalId",
      "number",
      "sourceType",
      "sourceId",
      "reversalId",
    ],
  },
  "accounting_period.closed": {
    subject: "accounting-periods",
    payload: [
      "organizationId",
      "id",
      "fiscalYear",
      "number",
      "startsOn",
      "endsOn",
    ],
  },
  "accounting_period.reopened": {
    subject: "accounting-periods",
    payload: [
      "organizationId",
      "id",
      "fiscalYear",
      "number",
      "startsOn",
      "endsOn",
      "reason",
    ],
  },
  "accounting_period.locked": {
    subject: "accounting-periods",
    payload: [
      "organizationId",
      "id",
      "fiscalYear",
      "number",
      "startsOn",
      "endsOn",
    ],
  },
  "accounting_period.unlocked": {
    subject: "accounting-periods",
    payload: [
      "organizationId",
      "id",
      "fiscalYear",
      "number",
      "startsOn",
      "endsOn",
      "reason",
    ],
  },
  "fiscal_year.closed": {
    subject: "fiscal-years",
    payload: ["organizationId", "fiscalYear", "closingEntryId"],
  },
  "accounting_budget.created": {
    subject: "accounting-budgets",
    payload: ["organizationId", "id", "name", "fiscalYear", "status"],
  },
  "accounting_budget.updated": {
    subject: "accounting-budgets",
    payload: ["organizationId", "id", "name", "fiscalYear", "status"],
  },
};

const tenantTable = { tenant: "tenant", export: true } as const;

const NAMES: BlockSqlNames = {
  entities: {
    accounting_account: {
      table: "accounts",
      singular: "accounting_account",
      primary: true,
    },
    accounting_journal: { table: "journals", singular: "accounting_journal" },
    accounting_period: { table: "periods", singular: "accounting_period" },
    accounting_entry: {
      table: "entries",
      singular: "accounting_entry",
      plural: "accounting_entries",
    },
    accounting_dimension: {
      table: "dimensions",
      singular: "accounting_dimension",
    },
    accounting_budget: { table: "budgets", singular: "accounting_budget" },
  },
  events: EVENTS,
  hooks: [
    "before_accounting_entry_post",
    "after_accounting_entry_post",
    "before_accounting_entry_reverse",
    "after_accounting_entry_reverse",
  ],
  options: [
    "extraColumns",
    "chart",
    "functionalCurrency",
    "fiscalYearStartMonth",
    "subtypes",
    "autoPost",
  ],
  tables: {
    settings: {
      name: "accounting_settings",
      app: {},
      lifecycle: tenantTable,
      columns: {
        tenant: "tenant_id",
        functionalCurrency: "functional_currency",
        fiscalYearStartMonth: "fiscal_year_start_month",
        lockDate: "lock_date",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    accounts: {
      name: "accounting_accounts",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        name: "name",
        type: "type",
        subtype: "subtype",
        parent: "parent_id",
        currency: "currency",
        reconcilable: "reconcilable",
        normalSide: "normal_side",
        level: "level",
        defaultTaxCode: "default_tax_code_id",
        active: "active",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    roles: {
      name: "accounting_account_roles",
      app: {},
      lifecycle: tenantTable,
      columns: {
        tenant: "tenant_id",
        role: "role",
        account: "account_id",
        updatedAt: "updated_at",
      },
    },
    journals: {
      name: "accounting_journals",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        code: "code",
        name: "name",
        type: "type",
        defaultAccount: "default_account_id",
        currency: "currency",
        contraAccount: "contra_account_id",
        bankAccount: "bank_account_id",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    periods: {
      name: "accounting_periods",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        fiscalYear: "fiscal_year",
        number: "number",
        startsOn: "starts_on",
        endsOn: "ends_on",
        status: "status",
        closedAt: "closed_at",
        closedBy: "closed_by",
        lockedAt: "locked_at",
        lockedBy: "locked_by",
        createdAt: "created_at",
      },
    },
    entries: {
      name: "accounting_entries",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        journal: "journal_id",
        fiscalYear: "fiscal_year",
        sequence: "sequence",
        number: "number",
        entryDate: "entry_date",
        period: "period_id",
        status: "status",
        reference: "reference",
        sourceType: "source_type",
        sourceId: "source_id",
        reverses: "reverses_id",
        memo: "memo",
        postedAt: "posted_at",
        postedBy: "posted_by",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    lines: {
      name: "accounting_entry_lines",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        entry: "entry_id",
        position: "position",
        account: "account_id",
        debit: "debit",
        credit: "credit",
        currency: "currency",
        amountCurrency: "amount_currency",
        fxRate: "fx_rate",
        taxCode: "tax_code_id",
        taxAmount: "tax_amount",
        party: "party_id",
        dimensions: "dimensions",
        description: "description",
      },
    },
    dimensions: {
      name: "accounting_dimensions",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        createdAt: "created_at",
      },
    },
    dimensionValues: {
      name: "accounting_dimension_values",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        dimension: "dimension_id",
        code: "code",
        name: "name",
        archivedAt: "archived_at",
      },
    },
    fxRates: {
      name: "accounting_fx_rates",
      app: {},
      lifecycle: tenantTable,
      columns: {
        tenant: "tenant_id",
        base: "base",
        quote: "quote",
        onDate: "on_date",
        rate: "rate",
        createdAt: "created_at",
      },
    },
    openingBalances: {
      name: "accounting_opening_balances",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        fiscalYear: "fiscal_year",
        account: "account_id",
        party: "party_id",
        amount: "amount",
        source: "source",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    budgets: {
      name: "accounting_budgets",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        fiscalYear: "fiscal_year",
        status: "status",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    budgetLines: {
      name: "accounting_budget_lines",
      app: {},
      lifecycle: tenantTable,
      columns: {
        id: "id",
        tenant: "tenant_id",
        budget: "budget_id",
        account: "account_id",
        periodNumber: "period_number",
        dimensions: "dimensions",
        amount: "amount",
      },
    },
  },
};

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  accountingConfig(ctx);

  return `${schemaPreamble(ctx)}
-- Accounting: a chart of accounts with roles, journals, fiscal periods, and
-- balanced journal entries in minor units of the organization's functional
-- currency, with dimensions, exchange rates, tax codes, reports and the
-- period and year-end close, the documents other blocks book, tax reports
-- and budgets.
${accountingTables(ctx)}${accountingSetupFunctions(ctx)}${accountingEntryFunctions(ctx)}${accountingPostingFunctions(ctx)}${accountingCloseFunctions(ctx)}${accountingReportFunctions(ctx)}${accountingLedgerReports(ctx)}${accountingOpeningFunctions(ctx)}${accountingImportFunctions(ctx)}${accountingTaxReport(ctx)}${accountingBudgets(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("entries", ENTRY_RESERVED),
  ).contract;

  return [
    {
      name: "setup_accounting",
      args: ["{id}", "text", "integer"],
      returns: "jsonb",
    },
    { name: "get_accounting_settings", args: ["{id}"], returns: "jsonb" },
    {
      name: "set_accounting_lock_date",
      args: ["{id}", "date"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_account",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        "text",
        "boolean",
        "uuid",
        "text",
        "uuid",
        "boolean",
      ],
      returns: "jsonb",
    },
    {
      name: "archive_accounting_account",
      args: ["uuid", "boolean"],
      returns: "jsonb",
    },
    {
      name: "set_accounting_account_role",
      args: ["{id}", "text", "uuid"],
      returns: "jsonb",
    },
    {
      name: "list_accounting_accounts",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_journal",
      args: [
        "{id}",
        "text",
        "text",
        "text",
        "uuid",
        "text",
        "uuid",
        "uuid",
        "uuid",
      ],
      returns: "jsonb",
    },
    { name: "list_accounting_journals", args: ["{id}"], returns: "jsonb" },
    { name: "lock_accounting_period", args: ["uuid"], returns: "jsonb" },
    {
      name: "unlock_accounting_period",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_opening_balances",
      args: ["{id}", "integer", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "list_accounting_opening_balances",
      args: ["{id}", "integer"],
      returns: "jsonb",
    },
    {
      name: "post_accounting_opening_balances",
      args: ["{id}", "integer", "uuid"],
      returns: "jsonb",
    },
    {
      name: "accounting_period_trial_balance",
      args: ["uuid", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "accounting_column_balance",
      args: ["{id}", "date", "date", "jsonb", "boolean"],
      returns: "jsonb",
    },
    {
      name: "accounting_journal_listing",
      args: ["{id}", "date", "date", "uuid"],
      returns: "jsonb",
    },
    { name: "open_fiscal_year", args: ["{id}", "integer"], returns: "jsonb" },
    {
      name: "list_accounting_periods",
      args: ["{id}", "integer"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_dimension",
      args: ["{id}", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_dimension_value",
      args: ["uuid", "text", "text", "boolean"],
      returns: "jsonb",
    },
    { name: "list_accounting_dimensions", args: ["{id}"], returns: "jsonb" },
    {
      name: "set_accounting_fx_rate",
      args: ["{id}", "text", "text", "date", "numeric"],
      returns: "jsonb",
    },
    {
      name: "accounting_fx_rate",
      args: ["{id}", "text", "text", "date"],
      returns: "numeric",
    },
    {
      name: "save_accounting_entry",
      args: [
        "uuid",
        "date",
        "jsonb",
        "text",
        "text",
        "text",
        "text",
        "uuid",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "post_accounting_entry", args: ["uuid"], returns: "jsonb" },
    {
      name: "reverse_accounting_entry",
      args: ["uuid", "date"],
      returns: "jsonb",
    },
    { name: "delete_accounting_entry", args: ["uuid"], returns: "jsonb" },
    { name: "get_accounting_entry", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_accounting_entries",
      args: ["{id}", "uuid", "text", "date", "date", "integer"],
      returns: "jsonb",
    },
    {
      name: "accounting_period_close_blockers",
      args: ["uuid"],
      returns: "text[]",
    },
    { name: "close_accounting_period", args: ["uuid"], returns: "jsonb" },
    {
      name: "reopen_accounting_period",
      args: ["uuid", "text"],
      returns: "jsonb",
    },
    { name: "close_fiscal_year", args: ["{id}", "integer"], returns: "jsonb" },
    {
      name: "accounting_trial_balance",
      args: ["{id}", "date", "date", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "accounting_profit_and_loss",
      args: ["{id}", "date", "date", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "accounting_balance_sheet",
      args: ["{id}", "date", "jsonb"],
      returns: "jsonb",
    },
    {
      name: "accounting_general_ledger",
      args: ["uuid", "date", "date"],
      returns: "jsonb",
    },
    {
      name: "post_accounting_source",
      args: ["text", "text"],
      returns: "jsonb",
    },
    {
      name: "accounting_tax_report",
      args: ["{id}", "date", "date"],
      returns: "jsonb",
    },
    {
      name: "save_accounting_budget",
      args: ["{id}", "text", "integer", "text", "jsonb", "uuid"],
      returns: "jsonb",
    },
    { name: "get_accounting_budget", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_accounting_budgets",
      args: ["{id}", "integer"],
      returns: "jsonb",
    },
    {
      name: "accounting_budget_vs_actual",
      args: ["uuid", "integer"],
      returns: "jsonb",
    },
  ];
}

export const ACCOUNTING: BlockSqlDefinition = {
  name: "accounting",
  scopes: ["tenant"],
  title: "Accounting",
  description:
    "Double-entry books: a chart of accounts with account roles, journals, fiscal years of periods, balanced journal entries numbered per journal and year, dimensions, exchange rates, tax codes, the trial balance, profit and loss, balance sheet and general ledger, the period and year-end close, entries booked from invoices, expenses, stock, rent and gifts, tax reports and budgets.",
  requires: ["memberships", "permissions", "tax"],
  integrates: ["outbox", "audit", "data-lifecycle", "banking"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  build,
  data: seedDisposalAccounts,
  contributes: { imports: accountingImportTargets },
};
