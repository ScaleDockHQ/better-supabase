import type { ExpensesEvents } from "../../blocks/expenses/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  lockTable,
  schemaPreamble,
} from "../shared.ts";
import {
  EXPENSE_REPORT_RESERVED,
  expensesFunctions,
} from "./expenses-functions.ts";
import { moduleOperations } from "./permissions-model.ts";

const REPORT_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "status",
  "total",
  "currency",
] as const;

const EVENTS: BlockSqlEvents<ExpensesEvents> = {
  "expense_report.created": {
    subject: "expense-reports",
    payload: REPORT_PAYLOAD,
  },
  "expense_report.submitted": {
    subject: "expense-reports",
    payload: [...REPORT_PAYLOAD, "approvalId"],
  },
  "expense_report.approved": {
    subject: "expense-reports",
    payload: [...REPORT_PAYLOAD, "transactionId"],
  },
  "expense_report.reimbursed": {
    subject: "expense-reports",
    payload: [...REPORT_PAYLOAD, "transactionId"],
  },
  "expense_report.cancelled": {
    subject: "expense-reports",
    payload: REPORT_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  entities: {
    expense_report: {
      table: "reports",
      singular: "expense_report",
      primary: true,
      subject: {
        title: "title",
        permissions: { read: "read", write: "manage" },
      },
    },
    expense_line: {
      table: "lines",
      singular: "expense_line",
      // Receipts attach to lines: members upload with expenses.submit.
      subject: {
        title: "description",
        permissions: { read: "read", write: "manage", upload: "submit" },
      },
    },
    expense_category: {
      table: "categories",
      singular: "expense_category",
      plural: "expense_categories",
    },
  },
  events: EVENTS,
  options: ["extraColumns"],
  tables: {
    categories: {
      name: "expense_categories",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        currency: "currency",
        limitAmount: "limit_amount",
        receiptOver: "receipt_over",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    reports: {
      name: "expense_reports",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        title: "title",
        currency: "currency",
        note: "note",
        approval: "approval_id",
        submittedAt: "submitted_at",
        approvedAt: "approved_at",
        approvalTransaction: "approval_transaction_id",
        reimbursedAt: "reimbursed_at",
        reimbursement: "reimbursement_transaction_id",
        cancelledAt: "cancelled_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    lines: {
      name: "expense_lines",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        report: "report_id",
        category: "category_id",
        spentOn: "spent_on",
        description: "description",
        merchant: "merchant",
        amount: "amount",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const approvals = ctx.of("approvals");
  const categories = ctx.table("categories");
  const reports = ctx.table("reports");
  const lines = ctx.table("lines");
  const k = (column: string): string => ctx.col("categories", column);
  const r = (column: string): string => ctx.col("reports", column);
  const x = (column: string): string => ctx.col("lines", column);
  const ops = moduleOperations("expenses");
  const read = ctx.permission("read", ops.read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  return `
-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists ${categories} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
  ${k("key")} text not null check (${k("key")} ~ '^[a-z][a-z0-9_]{0,62}$'),
  ${k("name")} text not null check (length(${k("name")}) between 1 and 200),
  ${k("currency")} char(3) check (${k("currency")} is null or ${k("currency")} ~ '^[A-Z]{3}$'),
  ${k("limitAmount")} bigint check (${k("limitAmount")} is null or ${k("limitAmount")} > 0),
  ${k("receiptOver")} bigint check (${k("receiptOver")} is null or ${k("receiptOver")} >= 0),
  ${k("archivedAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now(),
  unique (${k("tenant")}, ${k("key")}),
  unique (${k("tenant")}, ${k("id")}),
  check ((${k("limitAmount")} is null and ${k("receiptOver")} is null) or ${k("currency")} is not null)
);
${lockTable(categories, { read: true })}
drop policy if exists ${index("categories", "read")} on ${categories};
create policy ${index("categories", "read")} on ${categories} for select to authenticated
  using (${ctx.scope.check(k("tenant"), read)});

create table if not exists ${reports} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("user")} uuid not null references auth.users (id) on delete cascade,
  ${r("title")} text not null check (length(${r("title")}) between 1 and 200),
  ${r("currency")} char(3) not null check (${r("currency")} ~ '^[A-Z]{3}$'),
  ${r("note")} text check (${r("note")} is null or length(${r("note")}) <= 2000),
  ${r("approval")} uuid references ${approvals.table("requests")} (${approvals.col("requests", "id")}) on delete set null,
  ${r("submittedAt")} timestamptz,
  ${r("approvedAt")} timestamptz,
  ${r("approvalTransaction")} uuid,
  ${r("reimbursedAt")} timestamptz,
  ${r("reimbursement")} uuid,
  ${r("cancelledAt")} timestamptz,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now()
);${addExtraColumns(reports, ctx.extraColumns("reports", EXPENSE_REPORT_RESERVED))}
create index if not exists ${index("reports", "tenant_idx")} on ${reports} (${r("tenant")}, ${r("createdAt")} desc);
create index if not exists ${index("reports", "user_idx")} on ${reports} (${r("user")}, ${r("tenant")});
create index if not exists ${index("reports", "approval_idx")} on ${reports} (${r("approval")}) where ${r("approval")} is not null;
create index if not exists ${index("reports", "approval_tx_idx")} on ${reports} (${r("approvalTransaction")}) where ${r("approvalTransaction")} is not null;
create index if not exists ${index("reports", "reimbursement_idx")} on ${reports} (${r("reimbursement")}) where ${r("reimbursement")} is not null;
${lockTable(reports, { read: true })}
drop policy if exists ${index("reports", "read")} on ${reports};
create policy ${index("reports", "read")} on ${reports} for select to authenticated
  using (${r("user")} = (select auth.uid()) or ${ctx.scope.check(r("tenant"), read)});

create table if not exists ${lines} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("report")} uuid not null references ${reports} (${r("id")}) on delete cascade,
  ${x("category")} uuid not null,
  ${x("spentOn")} date not null,
  ${x("description")} text not null check (length(${x("description")}) between 1 and 500),
  ${x("merchant")} text check (${x("merchant")} is null or length(${x("merchant")}) <= 200),
  -- Minor units of the report's currency (ADR 0037).
  ${x("amount")} bigint not null check (${x("amount")} > 0),
  ${x("createdAt")} timestamptz not null default now(),
  ${x("updatedAt")} timestamptz not null default now(),
  foreign key (${x("tenant")}, ${x("category")}) references ${categories} (${k("tenant")}, ${k("id")}) on delete restrict
);
create index if not exists ${index("lines", "report_idx")} on ${lines} (${x("report")}, ${x("spentOn")});
create index if not exists ${index("lines", "category_idx")} on ${lines} (${x("tenant")}, ${x("category")});
${lockTable(lines, { read: true })}
drop policy if exists ${index("lines", "read")} on ${lines};
create policy ${index("lines", "read")} on ${lines} for select to authenticated
  using (
    exists (select 1 from ${reports} p where p.${r("id")} = ${x("report")} and p.${r("user")} = (select auth.uid()))
    or ${ctx.scope.check(x("tenant"), read)}
  );
`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  for (const needed of ["approvals", "ledger"]) {
    if (ctx.of(needed).mode === "custom") {
      throw new TypeError(
        `blocks.expenses needs the ${needed} tables; ${needed} can't be in custom mode`,
      );
    }
  }

  return `${schemaPreamble(ctx)}
-- Expenses: reports of lines in categories, spend policies checked on
-- submit, approval through the approvals block, and the approved total and
-- its reimbursement posted on the ledger.
${tables(ctx)}${expensesFunctions(ctx)}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(
    ctx.extraColumns("reports", EXPENSE_REPORT_RESERVED),
  ).contract;

  return [
    {
      name: "save_expense_category",
      args: ["{id}", "text", "text", "text", "bigint", "bigint"],
      returns: "jsonb",
    },
    { name: "archive_expense_category", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expense_categories",
      args: ["{id}", "boolean"],
      returns: "jsonb",
    },
    {
      name: "create_expense_report",
      args: ["{id}", "text", "text", "text", ...extra],
      returns: "jsonb",
    },
    {
      name: "add_expense_line",
      args: ["uuid", "uuid", "date", "bigint", "text", "text"],
      returns: "jsonb",
    },
    {
      name: "update_expense_line",
      args: ["uuid", "uuid", "date", "bigint", "text", "text"],
      returns: "jsonb",
    },
    { name: "remove_expense_line", args: ["uuid"], returns: "jsonb" },
    { name: "check_expense_report", args: ["uuid"], returns: "jsonb" },
    { name: "submit_expense_report", args: ["uuid"], returns: "jsonb" },
    {
      name: "reimburse_expense_report",
      args: ["uuid", "timestamptz", "text"],
      returns: "jsonb",
    },
    { name: "cancel_expense_report", args: ["uuid"], returns: "jsonb" },
    { name: "get_expense_report", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expense_reports",
      args: ["{id}", "uuid", "text", "boolean", "integer"],
      returns: "jsonb",
    },
  ];
}

export const EXPENSES: BlockSqlDefinition = {
  name: "expenses",
  scopes: ["tenant"],
  title: "Expenses",
  description:
    "Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units.",
  requires: ["memberships", "permissions", "approvals", "ledger"],
  integrates: ["outbox", "audit", "attachments"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  internal: ["approve_expense_report", "expense_report_violations"],
  build,
};
