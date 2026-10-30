import type { ExpensesEvents } from "../../blocks/expenses/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent } from "../../core/template.ts";
import {
  accountingContributions,
  accountingSourcesSql,
} from "../accounting-sources-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { addExtraColumns, extraFieldsArg, schemaPreamble } from "../shared.ts";
import { expenseAccountingSources } from "./expenses-accounting.ts";
import {
  EXPENSE_REPORT_RESERVED,
  EXPENSE_REPORT_SUBJECT,
  expenseApprovals,
  expenseCategoryExtras,
  expensesFunctions,
} from "./expenses-functions.ts";
import {
  EXPENSE_SUBJECT,
  EXPENSE_TABLE,
  expensesStandalone,
  standaloneApprovals,
  standaloneContract,
} from "./expenses-standalone.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { moduleOperations } from "./permissions-model.ts";

const REPORT_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "status",
  "total",
  "currency",
] as const;

const EXPENSE_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "status",
  "amount",
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
  "expense_report.rejected": {
    subject: "expense-reports",
    payload: REPORT_PAYLOAD,
  },
  "expense.created": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.submitted": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.approved": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.rejected": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.reimbursed": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.withdrawn": { subject: "expenses", payload: EXPENSE_PAYLOAD },
  "expense.deleted": { subject: "expenses", payload: EXPENSE_PAYLOAD },
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
  options: [
    "extraColumns",
    "categoryExtraColumns",
    "approvals",
    "owner",
    "companyExpenses",
    "withdrawApproved",
    "standaloneApprovals",
    "policy",
  ],
  tables: {
    categories: {
      name: "expense_categories",
      app: {},
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
      optional: ["key", "currency", "limitAmount", "receiptOver"],
    },
    reports: {
      name: "expense_reports",
      app: {},
      optionalTable: true,
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
        rejectedAt: "rejected_at",
        decidedBy: "decided_by",
        decisionNote: "decision_note",
      },
      optional: [
        "note",
        "approvalTransaction",
        "reimbursement",
        "approval",
        "rejectedAt",
        "decidedBy",
        "decisionNote",
      ],
    },
    lines: {
      name: "expense_lines",
      app: {},
      optionalTable: true,
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
      optional: ["merchant"],
    },
    expenses: EXPENSE_TABLE,
  },
};

function tables(ctx: BlockSqlContext): string {
  if (!ctx.manages) {
    return "";
  }

  const standalone = expensesStandalone(ctx);
  const approvals = expenseApprovals(ctx) ? ctx.of("approvals") : undefined;
  const categories = ctx.table("categories");
  const reports = standalone ? "" : ctx.table("reports");
  const lines = standalone ? "" : ctx.table("lines");
  const k = (column: string): string => ctx.col("categories", column);
  const r = (column: string): string => ctx.col("reports", column);
  const x = (column: string): string => ctx.col("lines", column);
  const ops = moduleOperations("expenses");
  const read = ctx.permission("read", ops.read);

  const index = (logical: string, suffix: string): string =>
    sqlIdent(`${ctx.tableName(logical).name}_${suffix}`);

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  // A partial index on a nullable column, left out without the column.
  const linkIndex = (suffix: string, logical: string): string =>
    ctx.has("reports", logical)
      ? `\ncreate index if not exists ${index("reports", suffix)} on ${reports} (${r(logical)}) where ${r(logical)} is not null;`
      : "";

  const policed = ["limitAmount", "receiptOver"].filter((logical) =>
    ctx.has("categories", logical),
  );

  const policyCheck =
    policed.length === 0
      ? ""
      : `,\n  check ((${policed.map((logical) => `${k(logical)} is null`).join(" and ")}) or ${k("currency")} is not null)`;

  return `
-- A category with its spend policy: limit_amount caps a report's total in
-- the category, receipt_over needs a receipt on any line above it.
create table if not exists ${categories} (
  ${k("id")} uuid primary key default gen_random_uuid(),
  ${k("tenant")} ${ctx.idType} not null,
${column("categories", "key", (name) => `${name} text not null check (${name} ~ '^[a-z][a-z0-9_]{0,62}$')`).slice(1)}
  ${k("name")} text not null check (length(${k("name")}) between 1 and 200),${column("categories", "currency", (name) => `${name} char(3) check (${name} is null or ${name} ~ '^[A-Z]{3}$')`)}${column("categories", "limitAmount", (name) => `${name} bigint check (${name} is null or ${name} > 0)`)}${column("categories", "receiptOver", (name) => `${name} bigint check (${name} is null or ${name} >= 0)`)}
  ${k("archivedAt")} timestamptz,
  ${k("createdAt")} timestamptz not null default now(),
  ${k("updatedAt")} timestamptz not null default now(),
${ctx.has("categories", "key") ? `  unique (${k("tenant")}, ${k("key")}),\n` : ""}  unique (${k("tenant")}, ${k("id")})${policyCheck}
);${addExtraColumns(categories, expenseCategoryExtras(ctx))}${ctx.has("categories", "key") ? appUniqueIndex(ctx, "categories", ["tenant", "key"]) : ""}${appUniqueIndex(ctx, "categories", ["tenant", "id"])}
${lockModuleTable(ctx, "categories", { read: true })}
drop policy if exists ${index("categories", "read")} on ${categories};
${renderPolicy(makePolicy({ table: categories, name: index("categories", "read"), command: "select", roles: ["authenticated"], using: ctx.scope.check(k("tenant"), read) }), { target: categories })}
${
  standalone
    ? ""
    : `
create table if not exists ${reports} (
  ${r("id")} uuid primary key default gen_random_uuid(),
  ${r("tenant")} ${ctx.idType} not null,
  ${r("user")} uuid not null references auth.users (id) on delete cascade,
  ${r("title")} text not null check (length(${r("title")}) between 1 and 200),
  ${r("currency")} char(3) not null check (${r("currency")} ~ '^[A-Z]{3}$'),${column("reports", "note", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
${approvals === undefined ? "" : `  ${r("approval")} uuid references ${approvals.table("requests")} (${approvals.col("requests", "id")}) on delete set null,\n`}  ${r("submittedAt")} timestamptz,${approvals === undefined ? `${column("reports", "rejectedAt", (name) => `${name} timestamptz`)}${column("reports", "decidedBy", (name) => `${name} uuid`)}${column("reports", "decisionNote", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}` : ""}
  ${r("approvedAt")} timestamptz,${column("reports", "approvalTransaction", (name) => `${name} uuid`)}
  ${r("reimbursedAt")} timestamptz,${column("reports", "reimbursement", (name) => `${name} uuid`)}
  ${r("cancelledAt")} timestamptz,
  ${r("createdAt")} timestamptz not null default now(),
  ${r("updatedAt")} timestamptz not null default now()
);${addExtraColumns(reports, ctx.extraColumns("reports", EXPENSE_REPORT_RESERVED))}
create index if not exists ${index("reports", "tenant_idx")} on ${reports} (${r("tenant")}, ${r("createdAt")} desc);
create index if not exists ${index("reports", "user_idx")} on ${reports} (${r("user")}, ${r("tenant")});
${approvals === undefined ? "" : `create index if not exists ${index("reports", "approval_idx")} on ${reports} (${r("approval")}) where ${r("approval")} is not null;`}${linkIndex("approval_tx_idx", "approvalTransaction")}${linkIndex("reimbursement_idx", "reimbursement")}
${lockModuleTable(ctx, "reports", { read: true })}
drop policy if exists ${index("reports", "read")} on ${reports};
${renderPolicy(makePolicy({ table: reports, name: index("reports", "read"), command: "select", roles: ["authenticated"], using: `${r("user")} = (select auth.uid()) or ${ctx.scope.check(r("tenant"), read)}` }), { target: reports })}

create table if not exists ${lines} (
  ${x("id")} uuid primary key default gen_random_uuid(),
  ${x("tenant")} ${ctx.idType} not null,
  ${x("report")} uuid not null references ${reports} (${r("id")}) on delete cascade,
  ${x("category")} uuid not null,
  ${x("spentOn")} date not null,
  ${x("description")} text not null check (length(${x("description")}) between 1 and 500),${column("lines", "merchant", (name) => `${name} text check (${name} is null or length(${name}) <= 200)`)}
  -- Minor units of the report's currency (ADR 0037).
  ${x("amount")} bigint not null check (${x("amount")} > 0),
  ${x("createdAt")} timestamptz not null default now(),
  ${x("updatedAt")} timestamptz not null default now(),
  foreign key (${x("tenant")}, ${x("category")}) references ${categories} (${k("tenant")}, ${k("id")}) on delete restrict
);
create index if not exists ${index("lines", "report_idx")} on ${lines} (${x("report")}, ${x("spentOn")});
create index if not exists ${index("lines", "category_idx")} on ${lines} (${x("tenant")}, ${x("category")});
${lockModuleTable(ctx, "lines", { read: true })}
drop policy if exists ${index("lines", "read")} on ${lines};
${renderPolicy(
  makePolicy({
    table: lines,
    name: index("lines", "read"),
    command: "select",
    roles: ["authenticated"],
    using: `exists (select 1 from ${reports} p where p.${r("id")} = ${x("report")} and p.${r("user")} = (select auth.uid()))
    or ${ctx.scope.check(x("tenant"), read)}`,
  }),
  { target: lines },
)}
`
}`;
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const approvals = expenseApprovals(ctx);
  const standalone = expensesStandalone(ctx);

  if (
    !ctx.has("categories", "currency") &&
    (ctx.has("categories", "limitAmount") ||
      ctx.has("categories", "receiptOver"))
  ) {
    throw new TypeError(
      "blocks.expenses: a category limit or receipt threshold needs the currency column; map limitAmount and receiptOver to null too",
    );
  }

  for (const needed of standalone
    ? []
    : approvals
      ? ["approvals", "ledger"]
      : ["ledger"]) {
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
${tables(ctx)}${expensesFunctions(ctx)}${accountingSourcesSql(ctx, expenseAccountingSources(ctx))}`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  if (expensesStandalone(ctx)) {
    return standaloneContract(ctx);
  }

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
    ...(expenseApprovals(ctx)
      ? []
      : [
          {
            name: "decide_expense_report",
            args: ["uuid", "boolean", "text", "uuid"],
            returns: "jsonb",
          },
        ]),
    { name: "get_expense_report", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expense_reports",
      args: ["{id}", "uuid", "text", "boolean", "integer"],
      returns: "jsonb",
    },
  ];
}

const CONTRIBUTES: BlockContributes = {
  accounting: (own) =>
    accountingContributions(own, expenseAccountingSources(own)),
  approvals: (own) =>
    standaloneApprovals(own)
      ? [
          {
            subject: EXPENSE_SUBJECT,
            access: "declared",
            approve: ({ subjectId, comment, approver }) =>
              `perform ${own.fn("expense_approval_decided")}(${subjectId}::uuid, true, ${comment}, ${approver});`,
            reject: ({ subjectId, comment, approver }) =>
              `perform ${own.fn("expense_approval_decided")}(${subjectId}::uuid, false, ${comment}, ${approver});`,
          },
        ]
      : expenseApprovals(own)
        ? [
            {
              subject: EXPENSE_REPORT_SUBJECT,
              access: "declared",
              approve: ({ subjectId }) =>
                `perform ${own.fn("approve_expense_report")}(${subjectId}::uuid);`,
            },
          ]
        : [],
};

const REQUIRES = ["memberships", "permissions", "approvals", "ledger"] as const;

export const EXPENSES: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  name: "expenses",
  scopes: ["tenant"],
  title: "Expenses",
  description:
    "Expense reports with lines in categories and receipts as attachments, spend policies (a limit per category, a receipt threshold) checked on submit, approval through the approvals block, and the approved total and its reimbursement posted on the ledger in bigint minor units. Without reports, each expense is one row a member or an employee submits and the app decides.",
  requires: [...REQUIRES],
  dependencies: (layout) => {
    const expenses = layout.modules?.["expenses"];

    if (expenses?.tables?.["reports"] === null) {
      return expenses.options?.["standaloneApprovals"] === true
        ? ["memberships", "permissions", "approvals"]
        : ["memberships", "permissions"];
    }

    return expenses?.options?.["approvals"] === false
      ? REQUIRES.filter((name) => name !== "approvals")
      : [...REQUIRES];
  },
  integrates: ["outbox", "audit", "attachments", "employees", "accounting"],
  target: "schema",
  modes: ["managed", "custom"],
  names: NAMES,
  contract,
  internal: ["approve_expense_report", "expense_report_violations"],
  build,
};
