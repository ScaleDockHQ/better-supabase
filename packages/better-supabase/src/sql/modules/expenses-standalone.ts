import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlTableSpec,
} from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  pageSize,
  SERVICE_CALLER,
  userGrant,
  updateExtraColumns,
} from "../shared.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { managerDecides } from "./direct-approver.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations, OPERATIONS } from "./permissions-model.ts";
import { ownerIsEmployee, recordOwner } from "./record-owner.ts";

export const expenseKey = (ctx: BlockSqlContext, action: string): string =>
  sqlString(
    ctx.config.permissions[action] ??
      ctx.permissionKey("manage", moduleOperations("expenses").manage),
  );

const EXPENSE_RESERVED = ["fields"] as const;

const STATUSES = ["draft", "submitted", "approved", "rejected", "reimbursed"];

export const EXPENSE_TABLE: BlockSqlTableSpec = {
  name: "expenses",
  app: {
    unused: (ctx) =>
      ownerIsEmployee(ctx, "blocks.expenses.options") ? [] : ["employee"],
  },
  optionalTable: true,
  columns: {
    id: "id",
    tenant: "tenant_id",
    user: "user_id",
    employee: "employee_id",
    category: "category_id",
    spentOn: "spent_on",
    description: "description",
    merchant: "merchant",
    amount: "amount",
    currency: "currency",
    status: "status",
    submittedAt: "submitted_at",
    approvedAt: "approved_at",
    rejectedAt: "rejected_at",
    decidedBy: "decided_by",
    decidedAt: "decided_at",
    decisionNote: "decision_note",
    reimbursedAt: "reimbursed_at",
    reimbursedBy: "reimbursed_by",
    reimbursement: "reimbursement_reference",
    createdBy: "created_by",
    createdAt: "created_at",
    updatedAt: "updated_at",
  },
  optional: [
    "user",
    "employee",
    "category",
    "description",
    "merchant",
    "status",
    "approvedAt",
    "rejectedAt",
    "decidedBy",
    "decidedAt",
    "decisionNote",
    "reimbursedBy",
    "reimbursement",
    "createdBy",
  ],
  typed: ["status"],
};

/** The subject type of an expense the approvals block decides. */
export const EXPENSE_SUBJECT = "expense";

/**
 * Whether each standalone expense goes through the approvals block:
 * `options.standaloneApprovals`, which needs `tables.reports: null`.
 */
export function standaloneApprovals(ctx: BlockSqlContext): boolean {
  const on = ctx.flag("standaloneApprovals", false);

  if (on && !expensesStandalone(ctx)) {
    throw new TypeError(
      "blocks.expenses.options.standaloneApprovals needs tables.reports: null; reports go through approvals already",
    );
  }

  return on;
}

/** `options.policy`, or one step for holders of the approve permission. */
function standalonePolicy(ctx: BlockSqlContext): string {
  const policy = policyOf(
    EXPENSE_SUBJECT,
    "approve",
    ctx.option("policy") ?? {
      steps: [
        {
          approvers: {
            permission: ctx.permissionKey(
              "approve",
              OPERATIONS["expenses.approve"],
            ),
          },
        },
      ],
    },
    "blocks.expenses.options.policy",
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      "blocks.expenses.options.policy.run is not allowed; the final approval approves the expense",
    );
  }

  return policySnapshot(policy);
}

export function expensesStandalone(ctx: BlockSqlContext): boolean {
  const reports = ctx.config.tables["reports"] === null;

  if (reports !== (ctx.config.tables["lines"] === null)) {
    throw new TypeError(
      "blocks.expenses.tables.reports and lines map to null together: without reports, each expense is one row of tables.expenses",
    );
  }

  return reports;
}

export function standaloneContract(
  ctx: BlockSqlContext,
): readonly BlockSqlContractFunction[] {
  const employee = ownerIsEmployee(ctx, "blocks.expenses.options")
    ? ["uuid"]
    : [];

  const company = ctx.flag("companyExpenses", false) ? ["boolean"] : [];

  const extra = extraFieldsArg(
    ctx.extraColumns("expenses", EXPENSE_RESERVED),
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
      name: "create_expense",
      args: [
        "{id}",
        "date",
        "bigint",
        "text",
        "uuid",
        "text",
        "text",
        "uuid",
        ...employee,
        ...company,
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "update_expense",
      args: [
        "uuid",
        "date",
        "bigint",
        "text",
        "uuid",
        "text",
        "text",
        "text[]",
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "submit_expense", args: ["uuid"], returns: "jsonb" },
    { name: "withdraw_expense", args: ["uuid"], returns: "jsonb" },
    { name: "delete_expense", args: ["uuid"], returns: "boolean" },
    {
      name: "decide_expense",
      args: ["uuid", "boolean", "text", "uuid"],
      returns: "jsonb",
    },
    { name: "reimburse_expense", args: ["uuid", "text"], returns: "jsonb" },
    { name: "get_expense", args: ["uuid"], returns: "jsonb" },
    {
      name: "list_expenses",
      args: ["{id}", "uuid", "text", "boolean", "integer", ...employee],
      returns: "jsonb",
    },
  ];
}

export function expenseStandaloneSql(ctx: BlockSqlContext): string {
  const owner = recordOwner(ctx, {
    block: "expenses",
    table: "expenses",
    noun: "expense",
    helper: "expense_is_mine",
  });

  const employee = owner.employee;
  const table = ctx.table("expenses");
  const e = (column: string): string => ctx.col("expenses", column);
  const has = (column: string): boolean => ctx.has("expenses", column);
  const categories = ctx.table("categories");
  const k = (column: string): string => ctx.col("categories", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const ops = moduleOperations("expenses");
  const read = ctx.permission("read", ops.read);
  const submit = ctx.permission("submit", ops.submit);
  const manage = ctx.permission("manage", ops.manage);
  const approve = ctx.permission("approve", ops.approve);
  const createOthers = expenseKey(ctx, "create");
  const updateOthers = expenseKey(ctx, "update");
  const deleteOthers = expenseKey(ctx, "delete");
  const reimburse = expenseKey(ctx, "reimburse");
  const withdrawApproved = ctx.flag("withdrawApproved", false);

  const withdrawOthers = sqlString(
    ctx.config.permissions["withdraw"] ??
      ctx.config.permissions["update"] ??
      ctx.permissionKey("manage", ops.manage),
  );

  const deleteSubmitted = ctx.config.permissions["deleteSubmitted"];
  const extras = ctx.extraColumns("expenses", EXPENSE_RESERVED);
  const extra = extraFieldsArg(extras);
  const statusColumn = has("status");
  const company = ctx.flag("companyExpenses", false);
  const linked = standaloneApprovals(ctx) ? ctx.of("approvals") : undefined;

  if (linked?.mode === "custom") {
    throw new TypeError(
      "blocks.expenses needs the approvals tables; approvals can't be in custom mode",
    );
  }

  const ar = linked?.table("requests") ?? "";
  const a = (column: string): string => linked?.col("requests", column) ?? "";

  // The pending approval request of v_row, when approvals decide expenses.
  const pending = `exists (select 1 from ${ar} x where x.${a("subjectType")} = ${sqlString(EXPENSE_SUBJECT)} and x.${a("subjectId")} = v_row.${e("id")}::text and x.${a("status")} = 'pending')`;

  const openApproval =
    linked === undefined
      ? ""
      : `
  perform ${linked.fn("open_approval")}(
    v_row.${e("tenant")}, ${sqlString(EXPENSE_SUBJECT)}, v_row.${e("id")}::text, 'approve',
    ${sqlString(standalonePolicy(ctx))}::jsonb${employee ? ` || jsonb_build_object('managerOf', v_row.${e("employee")}::text)` : ""}, null,
    jsonb_build_object('userId', ${owner.requester("v_row")}${employee ? `, 'employeeId', v_row.${e("employee")}` : ""}, 'amount', v_row.${e("amount")}::text, 'currency', v_row.${e("currency")}, 'spentOn', v_row.${e("spentOn")}),
    ${owner.requester("v_row")}
  );`;

  const cancelApproval =
    linked === undefined
      ? ""
      : `
  update ${ar} x set ${a("status")} = 'cancelled'${linked.has("requests", "decidedAt") ? `, ${a("decidedAt")} = now()` : ""}
    where x.${a("subjectType")} = ${sqlString(EXPENSE_SUBJECT)} and x.${a("subjectId")} = v_row.${e("id")}::text and x.${a("status")} = 'pending';`;

  const inserted = insertExtraColumns(
    table,
    extras,
    "coalesce(create_expense.fields, '{}'::jsonb)",
  );

  if (!statusColumn && !(has("approvedAt") && has("rejectedAt"))) {
    throw new TypeError(
      "blocks.expenses.columns.expenses needs a status column, or approvedAt and rejectedAt columns, to keep an expense's state",
    );
  }

  const forbidden = (message: string): string =>
    fail("EXPENSES_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("EXPENSE_INVALID", message, "22023");

  const or = (row: string, logical: string): string =>
    has(logical) ? `${row}.${e(logical)}` : "null";

  const set = (logical: string, value: string): string =>
    has(logical) ? `, ${e(logical)} = ${value}` : "";

  const unsupported = (logical: string, arg: string): string =>
    has(logical)
      ? ""
      : `
  if ${arg} is not null then
    ${fail("EXPENSE_COLUMN_UNSUPPORTED", `this expenses table has no ${logical} column`, "22023")}
  end if;`;

  const status = (row: string): string =>
    statusColumn
      ? `${row}.${e("status")}::text`
      : `(case when ${row}.${e("reimbursedAt")} is not null then 'reimbursed' when ${row}.${e("approvedAt")} is not null then 'approved' when ${row}.${e("rejectedAt")} is not null then 'rejected' when ${row}.${e("submittedAt")} is not null then 'submitted' else 'draft' end)`;

  const setStatus = (label: string): string =>
    statusColumn
      ? `, ${e("status")} = ${ctx.cast("expenses", "status", sqlString(label))}`
      : "";

  const userOf = (row: string): string =>
    has("user")
      ? `${row}.${e("user")}`
      : owner.userOf(`${row}.${e("employee")}`);

  const json = (row: string): string =>
    `jsonb_build_object('id', ${row}.${e("id")}, 'organizationId', ${row}.${e("tenant")}, 'userId', ${userOf(row)}${owner.json(row)}, 'categoryId', ${or(row, "category")}, 'spentOn', ${row}.${e("spentOn")}, 'description', ${or(row, "description")}, 'merchant', ${or(row, "merchant")}, 'amount', ${row}.${e("amount")}::text, 'currency', ${row}.${e("currency")}, 'status', ${status(row)}, 'submittedAt', ${row}.${e("submittedAt")}, 'decidedBy', ${or(row, "decidedBy")}, 'decidedAt', ${or(row, "decidedAt")}, 'decisionNote', ${or(row, "decisionNote")}, 'reimbursedAt', ${row}.${e("reimbursedAt")}, 'reimbursement', ${or(row, "reimbursement")}, 'createdAt', ${row}.${e("createdAt")}, 'updatedAt', ${row}.${e("updatedAt")}${extraFieldsJson(row, extras)})`;

  const record = (type: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', v_row.${e("tenant")}, 'id', v_row.${e("id")}, 'userId', ${userOf("v_row")}${owner.json("v_row")}, 'status', ${status("v_row")}, 'amount', v_row.${e("amount")}::text, 'currency', v_row.${e("currency")})`,
      subject: `'expenses/' || v_row.${e("id")}::text`,
      tenant: `v_row.${e("tenant")}`,
      audit: {
        category: "data",
        targetType: "expense",
        recordId: `v_row.${e("id")}::text`,
        summary: sqlString(summary),
      },
    });

  const load = (id: string): string => `
  select * into v_row from ${table} x where x.${e("id")} = ${id} for update;
  if not found then
    ${fail("EXPENSE_NOT_FOUND", "no such expense", "P0002")}
  end if;`;

  const mine = (row: string): string =>
    `(coalesce(${owner.requester(row)} = auth.uid(), false) and ${ctx.can("tenant", `${row}.${e("tenant")}`, submit)})`;

  const managed = (row: string, key: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${e("tenant")}`, key)}${employee ? ` or ${owner.manages(`${row}.${e("tenant")}`, `${row}.${e("employee")}`)}` : ""})`;

  const ownerOrManager = (key: string): string => `
  if not (${mine("v_row")} or ${managed("v_row", key)}) then
    ${forbidden("not allowed to change this expense")}
  end if;`;

  const editable = `
  if ${status("v_row")} not in ('draft', 'rejected') then
    ${fail("EXPENSE_LOCKED", "only a draft or rejected expense can change", "55000")}
  end if;`;

  const categoryCheck = (category: string, tenant: string): string =>
    has("category")
      ? `
  if ${category} is not null and not exists (select 1 from ${categories} c where c.${k("id")} = ${category} and c.${k("tenant")} = ${tenant} and c.${k("archivedAt")} is null) then
    ${fail("EXPENSE_CATEGORY_INVALID", "the category is unknown, archived or not in this organization", "22023")}
  end if;`
      : unsupported("category", category);

  const ownerInsert = employee
    ? `${has("user") ? `${e("user")}, ` : ""}${e("employee")}`
    : e("user");

  const ownerValues = employee
    ? `${has("user") ? "v_user, " : ""}v_owner`
    : "v_owner";

  const createBase = `${idType}, date, bigint, text, uuid, text, text, uuid`;
  const createTypes = `${createBase}${employee ? ", uuid" : ""}${company ? ", boolean" : ""}`;

  const createDrops = [false, true]
    .flatMap((withEmployee) =>
      [false, true].flatMap((withCompany) =>
        [false, true].map(
          (withFields) =>
            `${createBase}${withEmployee ? ", uuid" : ""}${withCompany ? ", boolean" : ""}${withFields ? ", jsonb" : ""}`,
        ),
      ),
    )
    .filter(
      (types) =>
        types !== createTypes && types !== `${createTypes}${extra.type}`,
    )
    .map(
      (types) => `drop function if exists ${fn("create_expense")}(${types});
`,
    )
    .join("");

  const updateBase = "uuid, date, bigint, text, uuid, text, text";
  const updateTypes = `${updateBase}, text[]`;

  const clearable = ["category", "description", "merchant"].filter((column) =>
    has(column),
  );

  const clears = (name: string): string =>
    `${sqlString(name)} = any (coalesce(update_expense.clear, '{}'::text[]))`;

  const listTypes = `${idType}, uuid, text, boolean, integer`;

  const ownTable = ctx.owns("expenses")
    ? `
create table if not exists ${table} (
  ${e("id")} uuid primary key default gen_random_uuid(),
  ${e("tenant")} ${idType} not null,
  ${employee ? `${has("user") ? `${e("user")} uuid,\n  ` : ""}${e("employee")} uuid${company ? "" : " not null"},` : `${e("user")} uuid${company ? "" : " not null"} references auth.users (id) on delete cascade,`}${has("category") ? `\n  ${e("category")} uuid,` : ""}
  ${e("spentOn")} date not null,${has("description") ? `\n  ${e("description")} text check (${e("description")} is null or length(${e("description")}) <= 500),` : ""}${has("merchant") ? `\n  ${e("merchant")} text check (${e("merchant")} is null or length(${e("merchant")}) <= 200),` : ""}
  ${e("amount")} bigint not null check (${e("amount")} >= 0),
  ${e("currency")} char(3) not null check (${e("currency")} ~ '^[A-Z]{3}$'),${statusColumn ? `\n  ${e("status")} text not null default 'draft' check (${e("status")} in (${STATUSES.map(sqlString).join(", ")})),` : ""}
  ${e("submittedAt")} timestamptz,${has("approvedAt") ? `\n  ${e("approvedAt")} timestamptz,` : ""}${has("rejectedAt") ? `\n  ${e("rejectedAt")} timestamptz,` : ""}${has("decidedBy") ? `\n  ${e("decidedBy")} uuid,` : ""}${has("decidedAt") ? `\n  ${e("decidedAt")} timestamptz,` : ""}${has("decisionNote") ? `\n  ${e("decisionNote")} text check (${e("decisionNote")} is null or length(${e("decisionNote")}) <= 2000),` : ""}
  ${e("reimbursedAt")} timestamptz,${has("reimbursedBy") ? `\n  ${e("reimbursedBy")} uuid,` : ""}${has("reimbursement") ? `\n  ${e("reimbursement")} text check (${e("reimbursement")} is null or length(${e("reimbursement")}) <= 200),` : ""}${has("createdBy") ? `\n  ${e("createdBy")} uuid,` : ""}
  ${e("createdAt")} timestamptz not null default now(),
  ${e("updatedAt")} timestamptz not null default now()${has("category") ? `,\n  foreign key (${e("tenant")}, ${e("category")}) references ${categories} (${k("tenant")}, ${k("id")}) on delete restrict` : ""}
);${addExtraColumns(table, extras)}${company ? `\nalter table ${table} alter column ${owner.column} drop not null;` : ""}
create index if not exists ${sqlIdent(`${ctx.tableName("expenses").name}_owner_idx`)} on ${table} (${e("tenant")}, ${owner.column}, ${e("spentOn")} desc);
${lockModuleTable(ctx, "expenses", { read: true })}
${renderPolicy(makePolicy({ table, name: ctx.naming.rename("expenses_read"), command: "select", roles: ["authenticated"], using: `${owner.mine} or ${ctx.scope.check(e("tenant"), read)}` }), { drop: true, target: table })}
`
    : "";

  return `${owner.helper}${ownTable}
${createDrops}create or replace function ${fn("create_expense")}(tenant ${idType}, spent_on date, amount bigint, currency text, category_id uuid default null, description text default null, merchant text default null, user_id uuid default null${employee ? ", employee_id uuid default null" : ""}${company ? ", company boolean default false" : ""}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_owner uuid;
  v_user uuid;
  v_row ${table}%rowtype;
begin
${
  company
    ? `  if coalesce(create_expense.company, false) then
    if create_expense.user_id is not null${employee ? " or create_expense.employee_id is not null" : ""} then
      ${invalid("a company expense has no member or employee")}
    end if;
    if not (${SERVICE_CALLER} or ${ctx.can("tenant", "create_expense.tenant", createOthers)}) then
      ${forbidden("not allowed to record company expenses")}
    end if;
  else
`
    : ""
}${
    employee
      ? `  ${owner.resolve("create_expense.tenant", "create_expense.user_id", "create_expense.employee_id")}
  if v_owner is null then
    ${fail("EXPENSE_EMPLOYEE_INVALID", "no employee record for that member in this organization", "22023")}
  end if;
  if not ((coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", "create_expense.tenant", submit)})
    or ${SERVICE_CALLER} or ${ctx.can("tenant", "create_expense.tenant", createOthers)} or ${owner.manages("create_expense.tenant", "v_owner")}) then
    ${forbidden("not allowed to record expenses for this employee")}
  end if;`
      : `  v_owner := coalesce(create_expense.user_id, auth.uid());
  v_user := v_owner;
  if v_owner is null then
    ${forbidden("sign in to record expenses")}
  end if;
  if not ((v_owner = auth.uid() and ${ctx.can("tenant", "create_expense.tenant", submit)})
    or ${SERVICE_CALLER} or ${ctx.can("tenant", "create_expense.tenant", createOthers)}) then
    ${forbidden("not allowed to record expenses for this member")}
  end if;
  if not ${owner.exists("create_expense.tenant", "v_owner")} then
    ${invalid("the user is not a member of this organization")}
  end if;`
  }${company ? "\n  end if;" : ""}
  if create_expense.spent_on is null then
    ${invalid("an expense needs spent_on")}
  end if;
  if create_expense.amount is null or create_expense.amount < 0 then
    ${invalid("an amount is zero or more minor units")}
  end if;
  if create_expense.currency is null or create_expense.currency !~ '^[A-Z]{3}$' then
    ${invalid("currency must be a three-letter currency code")}
  end if;${categoryCheck("create_expense.category_id", "create_expense.tenant")}${unsupported("description", "nullif(trim(create_expense.description), '')")}${unsupported("merchant", "nullif(trim(create_expense.merchant), '')")}
  insert into ${table} (${e("tenant")}, ${ownerInsert}${has("category") ? `, ${e("category")}` : ""}, ${e("spentOn")}${has("description") ? `, ${e("description")}` : ""}${has("merchant") ? `, ${e("merchant")}` : ""}, ${e("amount")}, ${e("currency")}${statusColumn ? `, ${e("status")}` : ""}${has("createdBy") ? `, ${e("createdBy")}` : ""}${inserted.columns})
  values (create_expense.tenant, ${ownerValues}${has("category") ? ", create_expense.category_id" : ""}, create_expense.spent_on${has("description") ? ", nullif(trim(create_expense.description), '')" : ""}${has("merchant") ? ", nullif(trim(create_expense.merchant), '')" : ""}, create_expense.amount, create_expense.currency${statusColumn ? `, ${ctx.cast("expenses", "status", "'draft'")}` : ""}${has("createdBy") ? ", auth.uid()" : ""}${inserted.values})
  returning * into v_row;
  ${record("expense.created", "recorded an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("create_expense")}(${createTypes}${extra.type})`)}

drop function if exists ${fn("update_expense")}(${updateBase});
${extra.drop(fn("update_expense"), updateTypes)}
create or replace function ${fn("update_expense")}(expense_id uuid, spent_on date default null, amount bigint default null, currency text default null, category_id uuid default null, description text default null, merchant text default null, clear text[] default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${table}%rowtype;
begin${load("update_expense.expense_id")}${ownerOrManager(updateOthers)}${editable}
  if update_expense.amount is not null and update_expense.amount < 0 then
    ${invalid("an amount is zero or more minor units")}
  end if;
  if update_expense.currency is not null and update_expense.currency !~ '^[A-Z]{3}$' then
    ${invalid("currency must be a three-letter currency code")}
  end if;
  if exists (select 1 from unnest(coalesce(update_expense.clear, '{}'::text[])) c where c <> all (${sqlString(`{${clearable.join(",")}}`)}::text[])) then
    ${invalid(`clear names only ${clearable.join(", ")}`)}
  end if;${categoryCheck("update_expense.category_id", `v_row.${e("tenant")}`)}${unsupported("description", "update_expense.description")}${unsupported("merchant", "update_expense.merchant")}
  update ${table} x set
    ${e("spentOn")} = coalesce(update_expense.spent_on, x.${e("spentOn")}),
    ${e("amount")} = coalesce(update_expense.amount, x.${e("amount")}),
    ${e("currency")} = coalesce(update_expense.currency, x.${e("currency")})${has("category") ? `,\n    ${e("category")} = case when ${clears("category")} then null else coalesce(update_expense.category_id, x.${e("category")}) end` : ""}${has("description") ? `,\n    ${e("description")} = case when ${clears("description")} then null else coalesce(nullif(trim(update_expense.description), ''), x.${e("description")}) end` : ""}${has("merchant") ? `,\n    ${e("merchant")} = case when ${clears("merchant")} then null else coalesce(nullif(trim(update_expense.merchant), ''), x.${e("merchant")}) end` : ""},
    ${e("updatedAt")} = now()${updateExtraColumns(table, extras, "update_expense.fields")}
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("update_expense")}(${updateTypes}${extra.type})`)}

create or replace function ${fn("submit_expense")}(expense_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("submit_expense.expense_id")}${ownerOrManager(updateOthers)}${editable}
  update ${table} x set ${e("submittedAt")} = now()${setStatus("submitted")}${set("rejectedAt", "null")}${set("approvedAt", "null")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${openApproval}
  ${record("expense.submitted", "submitted an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("submit_expense")}(uuid)`)}

create or replace function ${fn("withdraw_expense")}(expense_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("withdraw_expense.expense_id")}${ownerOrManager(withdrawApproved ? withdrawOthers : updateOthers)}
  if ${status("v_row")} not in (${withdrawApproved ? "'submitted', 'approved'" : "'submitted'"}) then
    ${fail("EXPENSE_LOCKED", withdrawApproved ? "only a submitted or approved expense is withdrawn" : "only a submitted expense is withdrawn", "55000")}
  end if;
  update ${table} x set ${e("submittedAt")} = null${setStatus("draft")}${withdrawApproved ? `${set("approvedAt", "null")}${set("decidedBy", "null")}${set("decidedAt", "null")}` : ""}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${cancelApproval}
  ${record("expense.withdrawn", "withdrew an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("withdraw_expense")}(uuid)`)}

create or replace function ${fn("delete_expense")}(expense_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("delete_expense.expense_id")}${
    deleteSubmitted === undefined
      ? ownerOrManager(deleteOthers)
      : `
  if ${status("v_row")} in ('submitted', 'approved') then
    if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${e("tenant")}`, sqlString(deleteSubmitted))}) then
      ${forbidden("not allowed to delete a submitted or approved expense")}
    end if;
  else${ownerOrManager(deleteOthers).replaceAll("\n", "\n  ")}
  end if;`
  }
  if ${status("v_row")} <> 'draft'${deleteSubmitted === undefined ? "" : ` and ${status("v_row")} not in ('submitted', 'approved')`} then
    ${fail("EXPENSE_LOCKED", deleteSubmitted === undefined ? "only a draft expense is deleted" : "only a draft, submitted or approved expense is deleted", "55000")}
  end if;
${cancelApproval}
  delete from ${table} x where x.${e("id")} = v_row.${e("id")};
  ${record("expense.deleted", "deleted an expense")}
  return true;
end;
$$;
${userGrant(`${fn("delete_expense")}(uuid)`)}

-- The service role names the user it decides for in decided_by.
drop function if exists ${fn("decide_expense")}(uuid, boolean, text);
create or replace function ${fn("decide_expense")}(expense_id uuid, approved boolean, note text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("decide_expense.expense_id")}
  if not (${SERVICE_CALLER} or ((${ctx.can("tenant", `v_row.${e("tenant")}`, approve)}${managerDecides(
    ctx,
    "blocks.expenses.options",
    {
      requester: owner.requester("v_row"),
      tenant: `v_row.${e("tenant")}`,
      ...(employee ? { employee: `v_row.${e("employee")}::text` } : {}),
    },
  )}) and ${owner.requester("v_row")} is distinct from auth.uid())) then
    ${forbidden("not allowed to decide this expense")}
  end if;
  if decide_expense.decided_by is not null and (not ${SERVICE_CALLER} and decide_expense.decided_by is distinct from auth.uid()
    or decide_expense.decided_by = ${owner.requester("v_row")}) then
    ${forbidden("only the service role decides for another user, never for the owner")}
  end if;
  if ${status("v_row")} <> 'submitted' then
    ${fail("EXPENSE_LOCKED", "only a submitted expense is decided", "55000")}
  end if;${
    linked === undefined
      ? ""
      : `
  if ${pending} then
    ${fail("EXPENSE_IN_APPROVAL", "this expense is decided through its approval request", "55000")}
  end if;`
  }
  if decide_expense.approved is null then
    ${invalid("approved must be true or false")}
  end if;${unsupported("decisionNote", "nullif(trim(decide_expense.note), '')")}
  if decide_expense.approved then
    update ${table} x set ${e("updatedAt")} = now()${setStatus("approved")}${set("approvedAt", "now()")}${set("decidedBy", "coalesce(decide_expense.decided_by, auth.uid())")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(decide_expense.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.approved", "approved an expense")}
  else
    update ${table} x set ${e("updatedAt")} = now()${setStatus("rejected")}${set("rejectedAt", "now()")}${set("decidedBy", "coalesce(decide_expense.decided_by, auth.uid())")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(decide_expense.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.rejected", "rejected an expense")}
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("decide_expense")}(uuid, boolean, text, uuid)`)}
${
  linked === undefined
    ? ""
    : `
-- Applies the final decision of an expense's approval request: approvals
-- calls it, with the user who decided. It isn't granted to anyone.
create or replace function ${fn("expense_approval_decided")}(expense_id uuid, approved boolean, note text, decided_by uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin
  select * into v_row from ${table} x where x.${e("id")} = expense_approval_decided.expense_id for update;
  if not found or ${status("v_row")} <> 'submitted' then
    return;
  end if;
  if expense_approval_decided.approved then
    update ${table} x set ${e("updatedAt")} = now()${setStatus("approved")}${set("approvedAt", "now()")}${set("decidedBy", "expense_approval_decided.decided_by")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(expense_approval_decided.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.approved", "approved an expense")}
  else
    update ${table} x set ${e("updatedAt")} = now()${setStatus("rejected")}${set("rejectedAt", "now()")}${set("decidedBy", "expense_approval_decided.decided_by")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(expense_approval_decided.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.rejected", "rejected an expense")}
  end if;
end;
$$;
revoke execute on function ${fn("expense_approval_decided")}(uuid, boolean, text, uuid) from public, anon, authenticated;
`
}
create or replace function ${fn("reimburse_expense")}(expense_id uuid, reference text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("reimburse_expense.expense_id")}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${e("tenant")}`, reimburse)}) then
    ${forbidden("not allowed to reimburse expenses")}
  end if;
  if ${status("v_row")} <> 'approved' then
    ${fail("EXPENSE_LOCKED", "only an approved expense is reimbursed", "55000")}
  end if;${unsupported("reimbursement", "nullif(trim(reimburse_expense.reference), '')")}
  update ${table} x set ${e("reimbursedAt")} = now()${setStatus("reimbursed")}${set("reimbursedBy", "auth.uid()")}${set("reimbursement", "nullif(trim(reimburse_expense.reference), '')")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${record("expense.reimbursed", "reimbursed an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("reimburse_expense")}(uuid, text)`)}

create or replace function ${fn("get_expense")}(expense_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin
  select * into v_row from ${table} x where x.${e("id")} = get_expense.expense_id;
  if not found or not (coalesce(${owner.requester("v_row")} = auth.uid(), false) or ${managed("v_row", manage)} or ${ctx.can("tenant", `v_row.${e("tenant")}`, read)}) then
    ${fail("EXPENSE_NOT_FOUND", "no such expense", "P0002")}
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("get_expense")}(uuid)`)}

${employee ? `drop function if exists ${fn("list_expenses")}(${listTypes});\n` : ""}create or replace function ${fn("list_expenses")}(tenant ${idType}, user_id uuid default null, status text default null, everyone boolean default false, page_size integer default 100${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "list_expenses.tenant", read)};
  v_owner uuid;
  v_user uuid;
begin
${
  employee
    ? `  ${owner.resolve("list_expenses.tenant", "list_expenses.user_id", "list_expenses.employee_id")}
  if not v_reader and (coalesce(list_expenses.everyone, false)
    or not ((coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", "list_expenses.tenant", submit)}) or ${owner.manages("list_expenses.tenant", "v_owner")})) then
    ${forbidden("not allowed to read this employee's expenses")}
  end if;`
    : `  v_owner := coalesce(list_expenses.user_id, auth.uid());
  if not v_reader and (coalesce(list_expenses.everyone, false) or v_owner is distinct from auth.uid()
    or not ${ctx.can("tenant", "list_expenses.tenant", submit)}) then
    ${forbidden("not allowed to read another member's expenses")}
  end if;`
}
  return (
    select coalesce(jsonb_agg(z.item order by z.spent desc, z.created desc), '[]'::jsonb)
    from (
      select ${json("q")} as item, q.${e("spentOn")} as spent, q.${e("createdAt")} as created
      from ${table} q
      where q.${e("tenant")} = list_expenses.tenant
        and (coalesce(list_expenses.everyone, false) or q.${owner.column} = v_owner)
        and (list_expenses.status is null or ${status("q")} = list_expenses.status)
      order by q.${e("spentOn")} desc, q.${e("createdAt")} desc
      limit ${pageSize("list_expenses.page_size", 100, 500)}
    ) z
  );
end;
$$;
${userGrant(`${fn("list_expenses")}(${listTypes}${employee ? ", uuid" : ""})`)}
`;
}
