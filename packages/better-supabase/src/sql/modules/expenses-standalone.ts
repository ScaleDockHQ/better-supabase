import type { BlockSqlContext, BlockSqlTableSpec } from "../context.ts";
import type { BlockSqlUpgrade } from "../module-types.ts";
import type { ApprovalPolicy } from "./approvals-policies.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  conflict,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  pageSize,
  SERVICE_CALLER,
  userGrant,
  updateExtraColumns,
} from "../shared.ts";
import {
  assertCountedApprovers,
  policyOf,
  policySnapshot,
} from "./approvals-policies.ts";
import { otherDecider } from "./approvals-tenant.ts";
import { appFunction, deciderCall, managerDecides } from "./direct-approver.ts";
import {
  EXPENSE_RESERVED,
  invoicedCheck,
} from "./expenses-standalone-contract.ts";
import { expenseGuardSql } from "./expenses-write-guard.ts";
import { lockModuleTable } from "./over-app.ts";
import { moduleOperations, OPERATIONS } from "./permissions-model.ts";
import { ownerIsEmployee, recordOwner } from "./record-owner.ts";

export const expenseKey = (ctx: BlockSqlContext, action: string): string =>
  sqlString(
    ctx.config.permissions[action] ??
      ctx.permissionKey("manage", moduleOperations("expenses").manage),
  );

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

  if (!on && ctx.flag("selfDecideWhenTopOfChain", false)) {
    throw new TypeError(
      "blocks.expenses.options.selfDecideWhenTopOfChain needs standaloneApprovals; decideExpense already lets the owner decide when nobody else can",
    );
  }

  return on;
}

/**
 * `options.policy`, or one step for holders of the approve permission and, with
 * `options.decider`, whoever the app's decider accepts.
 */
function standalonePolicy(ctx: BlockSqlContext): string {
  const policy = standalonePolicyOf(ctx);

  if (ctx.flag("selfDecideWhenTopOfChain", false)) {
    assertCountedApprovers(
      policy,
      ctx.permissionKey("approve", OPERATIONS["expenses.approve"]),
      "blocks.expenses.options.selfDecideWhenTopOfChain",
    );
  }

  return policySnapshot(policy);
}

function standalonePolicyOf(ctx: BlockSqlContext): ApprovalPolicy {
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
            ...(ctx.text("decider", "") === "" ? {} : { decider: true }),
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

  return policy;
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

  // permissions.purge, then the delete key it replaces, then manage.
  const purgeOthers = sqlString(
    ctx.config.permissions["purge"] ??
      ctx.config.permissions["delete"] ??
      ctx.permissionKey("manage", ops.manage),
  );

  const reimburse = expenseKey(ctx, "reimburse");
  const invoiced = invoicedCheck(ctx);

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

  // `exclude` adds to the policy snapshot, such as the users to leave out.
  const openApprovalWith = (exclude: string): string =>
    linked === undefined
      ? ""
      : `
  perform ${linked.fn("open_approval")}(
    v_row.${e("tenant")}, ${sqlString(EXPENSE_SUBJECT)}, v_row.${e("id")}::text, 'approve',
    ${sqlString(standalonePolicy(ctx))}::jsonb${employee ? ` || jsonb_build_object('managerOf', v_row.${e("employee")}::text)` : ""}${exclude}, null,
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

  const payload = `jsonb_build_object('organizationId', v_row.${e("tenant")}, 'id', v_row.${e("id")}, 'userId', ${userOf("v_row")}${owner.json("v_row")}, 'status', ${status("v_row")}, 'amount', v_row.${e("amount")}::text, 'currency', v_row.${e("currency")})`;

  // `metadata` adds keys to the audit entry only, such as a reason.
  const record = (
    type: string,
    summary: string,
    metadata?: { readonly summary: string; readonly keys: string },
  ): string =>
    ctx.record({
      type,
      payload,
      subject: `'expenses/' || v_row.${e("id")}::text`,
      tenant: `v_row.${e("tenant")}`,
      audit: {
        category: "data",
        targetType: "expense",
        recordId: `v_row.${e("id")}::text`,
        summary: metadata?.summary ?? sqlString(summary),
        ...(metadata === undefined
          ? {}
          : { metadata: `${payload} || jsonb_build_object(${metadata.keys})` }),
      },
    });

  const selfAudit = (verb: string) =>
    ({
      summary: `case when v_self then ${sqlString(`${verb} an expense nobody else could decide (self-decided)`)} else ${sqlString(`${verb} an expense`)} end`,
      keys: "'selfDecided', v_self",
    }) as const;

  const load = (id: string): string => `
  select * into v_row from ${table} x where x.${e("id")} = ${id} for update;
  if not found then
    ${fail("EXPENSE_NOT_FOUND", "no such expense", "P0002")}
  end if;`;

  const mine = (row: string): string =>
    `(coalesce(${owner.requester(row)} = auth.uid(), false) and ${ctx.can("tenant", `${row}.${e("tenant")}`, submit)})`;

  const expenseIdKey = {
    expr: `x.${e("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const expenseSpentKeys = [
    { expr: `x.${e("spentOn")}`, dir: "desc", type: "date" },
    { expr: `x.${e("createdAt")}`, dir: "desc", type: "timestamptz" },
    expenseIdKey,
  ] as const;

  const expensePage = {
    name: "page_expenses",
    from: table,
    alias: "x",
    where: [
      `x.${e("tenant")} = page_expenses.tenant`,
      `((v_reader and not ${filterFlag("mine")}) or ${mine("x")})`,
      filterAny("userId", `${userOf("x")}::text`),
      filterAny("status", status("x")),
      filterAny("currency", `x.${e("currency")}`),
      ...(has("category")
        ? [filterAny("categoryId", `x.${e("category")}::text`)]
        : []),
      `(v_search is null or x.${e("description")} ilike v_search${has("merchant") ? ` or x.${e("merchant")} ilike v_search` : ""})`,
    ],
    keys: expenseSpentKeys,
    sorts: {
      spentOn: expenseSpentKeys,
      amount: [
        { expr: `x.${e("amount")}`, dir: "desc", type: "bigint" },
        expenseIdKey,
      ],
      createdAt: [
        { expr: `x.${e("createdAt")}`, dir: "desc", type: "timestamptz" },
        expenseIdKey,
      ],
    },
    facets: { status: status("x"), currency: `x.${e("currency")}` },
    rowJson: json("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("EXPENSE_INVALID", message, "22023"),
  } as const;

  const managed = (row: string, key: string): string =>
    `(${SERVICE_CALLER} or ${ctx.can("tenant", `${row}.${e("tenant")}`, key)}${employee ? ` or ${owner.manages(`${row}.${e("tenant")}`, `${row}.${e("employee")}`)}` : ""})`;

  // The creator to keep out of a decision. An expense without one, such as an
  // owner-less company expense, has nobody to keep out (ADR 1093).
  const creatorOf = (row: string): string =>
    has("createdBy") ? `${row}.${e("createdBy")}` : "null";

  // Whether `decider` decides this expense as its owner or creator.
  const selfOf = (row: string, decider: string): string =>
    `coalesce(${decider} = ${owner.requester(row)} or ${decider} = ${creatorOf(row)}, false)`;

  const managerArgs = (row: string) =>
    ({
      requester: owner.requester(row),
      tenant: `${row}.${e("tenant")}`,
      ...(employee ? { employee: `${row}.${e("employee")}::text` } : {}),
    }) as const;

  // Who may decide: the approve key, the owner's manager (options.approver),
  // or a caller the app's options.decider function accepts.
  const decides = (row: string): string =>
    `(${ctx.can("tenant", `${row}.${e("tenant")}`, approve)}${managerDecides(ctx, "blocks.expenses.options", managerArgs(row))}${deciderCall(ctx, "blocks.expenses.options", `${row}.${e("id")}`)})`;

  const deciderOn = deciderCall(ctx, "blocks.expenses.options", "null") !== "";

  // Another active member who holds the approve key, or, with the manager as
  // approver, an active manager up the owner's chain. The owner or creator
  // decides only without one; an access model that can't answer for other
  // users never lets them.
  const answersForOthers = !(
    (ctx.modules.permissions?.model === "custom" &&
      ctx.modules.permissions.functions?.canUser === undefined) ||
    ctx.providerCallerOnly === true
  );

  const managerOn =
    managerDecides(ctx, "blocks.expenses.options", managerArgs("v_row")) !== "";

  // `also` is the creator to leave out, next to the owner.
  const nobodyElse = (row: string, also: string): string => {
    const other = answersForOthers
      ? otherDecider(ctx, {
          ...managerArgs(row),
          permission: approve,
          manager: managerOn,
          // Without options.decider only the direct manager decides
          // (managerDecides), so a manager higher up would leave the expense
          // with nobody. An app's decider may accept the chain, as in leave.
          chain: deciderOn,
          also,
        })
      : undefined;

    return other === undefined ? "false" : `not ${other}`;
  };

  // The approvals queue leaves the creator out while someone else can decide.
  const cb = has("createdBy") ? `v_row.${e("createdBy")}` : "";

  // Without a policy column the snapshot can't carry the list; the creator
  // still can't decide (expense_approval_decided).
  const filing = openApprovalWith(
    has("createdBy") && linked?.has("requests", "policy") === true
      ? ` || case when ${cb} is not null and ${cb} is distinct from ${owner.requester("v_row")} and not ${nobodyElse("v_row", cb)} then jsonb_build_object('excludedUserIds', jsonb_build_array(${cb}::text)) else '{}'::jsonb end`
      : "",
  );

  // options.approvalRequired: an app function whose false approves the
  // submitted expense at once, without an approval request.
  const required =
    linked === undefined
      ? undefined
      : appFunction(ctx, "blocks.expenses.options", "approvalRequired");

  if (linked === undefined && ctx.text("approvalRequired", "") !== "") {
    throw new TypeError(
      "blocks.expenses.options.approvalRequired needs standaloneApprovals",
    );
  }

  const needed = `coalesce(${required ?? ""}(v_row.${e("tenant")}, v_row.${e("id")}), true)`;

  const openApproval =
    required === undefined
      ? filing
      : `
  if ${needed} then${filing.replaceAll("\n  ", "\n    ")}
  end if;`;

  // Approves the expense at once when options.approvalRequired answers false.
  const approvedAtOnce =
    required === undefined
      ? ""
      : `
  if not ${needed} then
    perform ${fn("expense_approval_decided")}(v_row.${e("id")}, true, null, null);
    select * into v_row from ${table} x where x.${e("id")} = v_row.${e("id")};
  end if;`;

  const ownerOrManager = (key: string): string => `
  if not (${mine("v_row")} or ${managed("v_row", key)}) then
    ${forbidden("not allowed to change this expense")}
  end if;`;

  const editable = `
  if ${status("v_row")} not in ('draft', 'rejected') then
    ${conflict("EXPENSE_LOCKED", "only a draft or rejected expense can change")}
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
  const createTypes = `${createBase}${employee ? ", uuid" : ""}${company ? ", boolean" : ""}, uuid`;

  const createDrops = [false, true]
    .flatMap((withEmployee) =>
      [false, true].flatMap((withCompany) =>
        [false, true].flatMap((withCreator) =>
          [false, true].map(
            (withFields) =>
              `${createBase}${withEmployee ? ", uuid" : ""}${withCompany ? ", boolean" : ""}${withCreator ? ", uuid" : ""}${withFields ? ", jsonb" : ""}`,
          ),
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

  const guard = expenseGuardSql(ctx, {
    status,
    forbidden,
    owners: employee
      ? [...(has("user") ? ["user"] : []), "employee"]
      : ["user"],
    createOthers,
    updateOthers,
    requester: owner.requester,
  });

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
);${company ? `\nalter table ${table} alter column ${owner.column} drop not null;` : ""}
create index if not exists ${sqlIdent(`${ctx.tableName("expenses").name}_owner_idx`)} on ${table} (${e("tenant")}, ${owner.column}, ${e("spentOn")} desc);
${lockModuleTable(ctx, "expenses", { read: true })}
${renderPolicy(makePolicy({ table, name: ctx.naming.rename("expenses_read"), command: "select", roles: ["authenticated"], using: `${owner.mine} or ${ctx.scope.check(e("tenant"), read)}` }), { target: table })}
`
    : "";

  return `${owner.helper}${ownTable}
${createDrops}create or replace function ${fn("create_expense")}(tenant ${idType}, spent_on date, amount bigint, currency text, category_id uuid default null, description text default null, merchant text default null, user_id uuid default null${employee ? ", employee_id uuid default null" : ""}${company ? ", company boolean default false" : ""}, created_by uuid default null${extra.param})
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
  if create_expense.created_by is not null and not ${SERVICE_CALLER} and create_expense.created_by is distinct from auth.uid() then
    ${forbidden("only the service role records an expense for another creator")}
  end if;${unsupported("createdBy", "create_expense.created_by")}
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
  values (create_expense.tenant, ${ownerValues}${has("category") ? ", create_expense.category_id" : ""}, create_expense.spent_on${has("description") ? ", nullif(trim(create_expense.description), '')" : ""}${has("merchant") ? ", nullif(trim(create_expense.merchant), '')" : ""}, create_expense.amount, create_expense.currency${statusColumn ? `, ${ctx.cast("expenses", "status", "'draft'")}` : ""}${has("createdBy") ? `, coalesce(create_expense.created_by${extra.param === "" ? "" : `, case when ${SERVICE_CALLER} then nullif(create_expense.fields ->> ${sqlString(ctx.colName("expenses", "createdBy"))}, '')::uuid end`}, auth.uid())` : ""}${inserted.values})
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

${guard}
create or replace function ${fn("submit_expense")}(expense_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("submit_expense.expense_id")}${ownerOrManager(updateOthers)}
  if ${status("v_row")} = 'submitted' then
    ${conflict("EXPENSE_ALREADY_SUBMITTED", "this expense is already submitted")}
  end if;
  if ${status("v_row")} in ('approved', 'reimbursed') then
    ${conflict("EXPENSE_ALREADY_DECIDED", "this expense is already decided")}
  end if;${editable}
  if ${status("v_row")} = 'rejected' and not ${mine("v_row")} then
    ${forbidden("only the owner resubmits a rejected expense")}
  end if;
  update ${table} x set ${e("submittedAt")} = now()${setStatus("submitted")}${set("rejectedAt", "null")}${set("approvedAt", "null")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${openApproval}
  ${record("expense.submitted", "submitted an expense")}${approvedAtOnce}
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
begin${load("withdraw_expense.expense_id")}${ownerOrManager(withdrawOthers)}
  if ${status("v_row")} in ('approved', 'rejected', 'reimbursed') then
    ${conflict("EXPENSE_ALREADY_DECIDED", "this expense is already decided; it can't be withdrawn")}
  end if;
  if ${status("v_row")} <> 'submitted' then
    ${conflict("EXPENSE_LOCKED", "only a submitted expense is withdrawn")}
  end if;
  update ${table} x set ${e("submittedAt")} = null${setStatus("draft")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${cancelApproval}
  ${record("expense.withdrawn", "withdrew an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("withdraw_expense")}(uuid)`)}

-- Removes a draft expense for good (a submitted or approved one with
-- permissions.deleteSubmitted). Its owner may, or a holder of permissions.purge
-- (falling back to delete, then manage). A rejected or reimbursed expense is a
-- record of what was claimed, so it stays: its status is the archive (ADR 1082).
create or replace function ${fn("purge_expense")}(expense_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("purge_expense.expense_id")}${
    deleteSubmitted === undefined
      ? ownerOrManager(purgeOthers)
      : `
  if ${status("v_row")} in ('submitted', 'approved') then
    if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${e("tenant")}`, sqlString(deleteSubmitted))}) then
      ${forbidden("not allowed to purge a submitted or approved expense")}
    end if;
  else${ownerOrManager(purgeOthers).replaceAll("\n", "\n  ")}
  end if;`
  }
  if ${status("v_row")} <> 'draft'${deleteSubmitted === undefined ? "" : ` and ${status("v_row")} not in ('submitted', 'approved')`} then
    ${conflict("EXPENSE_LOCKED", deleteSubmitted === undefined ? "only a draft expense is purged" : "only a draft, submitted or approved expense is purged")}
  end if;
${cancelApproval}
  delete from ${table} x where x.${e("id")} = v_row.${e("id")};
  ${record("expense.purged", "purged an expense")}
  return true;
end;
$$;
${userGrant(`${fn("purge_expense")}(uuid)`)}

-- The service role names the user it decides for in decided_by. The owner or
-- creator decides only when nobody else can (ADR 1090); the audit entry says so.
drop function if exists ${fn("decide_expense")}(uuid, boolean, text);
create or replace function ${fn("decide_expense")}(expense_id uuid, approved boolean, note text default null, decided_by uuid default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
  v_decider uuid;
  v_self boolean;
begin${load("decide_expense.expense_id")}
  if not (${SERVICE_CALLER} or ${decides("v_row")}) then
    ${forbidden("not allowed to decide this expense")}
  end if;
  if decide_expense.decided_by is not null and not ${SERVICE_CALLER} and decide_expense.decided_by is distinct from auth.uid() then
    ${forbidden("only the service role decides for another user")}
  end if;
  v_decider := coalesce(decide_expense.decided_by, auth.uid());
  v_self := ${selfOf("v_row", "v_decider")};
  if v_self and not ${nobodyElse("v_row", creatorOf("v_row"))} then
    ${forbidden("not allowed to decide this expense: its owner or creator decides only when nobody else can")}
  end if;
  if ${status("v_row")} in ('approved', 'rejected', 'reimbursed') then
    ${conflict("EXPENSE_ALREADY_DECIDED", "this expense is already decided")}
  end if;
  if ${status("v_row")} <> 'submitted' then
    ${conflict("EXPENSE_LOCKED", "only a submitted expense is decided")}
  end if;${
    linked === undefined
      ? ""
      : `
  if ${pending} then
    ${conflict("EXPENSE_IN_APPROVAL", "this expense is decided through its approval request")}
  end if;`
  }
  if decide_expense.approved is null then
    ${invalid("approved must be true or false")}
  end if;${unsupported("decisionNote", "nullif(trim(decide_expense.note), '')")}
  if decide_expense.approved then
    update ${table} x set ${e("updatedAt")} = now()${setStatus("approved")}${set("approvedAt", "now()")}${set("decidedBy", "coalesce(decide_expense.decided_by, auth.uid())")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(decide_expense.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.approved", "approved an expense", selfAudit("approved"))}
  else
    update ${table} x set ${e("updatedAt")} = now()${setStatus("rejected")}${set("rejectedAt", "now()")}${set("decidedBy", "coalesce(decide_expense.decided_by, auth.uid())")}${set("decidedAt", "now()")}${set("decisionNote", "nullif(trim(decide_expense.note), '')")}
      where x.${e("id")} = v_row.${e("id")}
      returning * into v_row;
    ${record("expense.rejected", "rejected an expense", selfAudit("rejected"))}
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
  -- Approvals keeps the owner, its requester, out; this keeps the creator out
  -- unless nobody else can decide (ADR 1090).
  if expense_approval_decided.decided_by is not null and expense_approval_decided.decided_by = ${creatorOf("v_row")}
    and expense_approval_decided.decided_by is distinct from ${owner.requester("v_row")} and not ${nobodyElse("v_row", creatorOf("v_row"))} then
    ${forbidden("not allowed to decide this expense: its owner or creator decides only when nobody else can")}
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
  if ${status("v_row")} = 'reimbursed' then
    ${conflict("EXPENSE_ALREADY_REIMBURSED", "this expense is already reimbursed")}
  end if;
  if ${status("v_row")} <> 'approved' then
    ${conflict("EXPENSE_LOCKED", "only an approved expense is reimbursed")}
  end if;${unsupported("reimbursement", "nullif(trim(reimburse_expense.reference), '')")}
  update ${table} x set ${e("reimbursedAt")} = now()${setStatus("reimbursed")}${set("reimbursedBy", "auth.uid()")}${set("reimbursement", "nullif(trim(reimburse_expense.reference), '')")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${record("expense.reimbursed", "reimbursed an expense")}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("reimburse_expense")}(uuid, text)`)}

-- Takes an approved expense back to submitted for a new decision, with a
-- reason the audit keeps. A decider who isn't the owner or creator may (they
-- too when nobody else can decide), until it is
-- reimbursed${invoiced === undefined ? "" : " or invoiced"}.
create or replace function ${fn("reopen_expense")}(expense_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("reopen_expense.expense_id")}
  if not (${SERVICE_CALLER} or (${decides("v_row")} and (not ${selfOf("v_row", "auth.uid()")} or ${nobodyElse("v_row", creatorOf("v_row"))}))) then
    ${forbidden("not allowed to reopen this expense")}
  end if;
  if nullif(trim(reopen_expense.reason), '') is null then
    ${invalid("reopening an expense needs a reason")}
  end if;
  if ${status("v_row")} = 'submitted' then
    ${conflict("EXPENSE_ALREADY_OPEN", "this expense is already open for a decision")}
  end if;
  if ${status("v_row")} = 'reimbursed' then
    ${conflict("EXPENSE_ALREADY_REIMBURSED", "a reimbursed expense can't be reopened")}
  end if;
  if ${status("v_row")} <> 'approved' then
    ${conflict("EXPENSE_LOCKED", "only an approved expense is reopened")}
  end if;${
    invoiced === undefined
      ? ""
      : `
  if ${invoiced("v_row")} then
    ${conflict("EXPENSE_INVOICED", "an invoiced expense can't be reopened")}
  end if;`
  }
  update ${table} x set ${e("submittedAt")} = now()${setStatus("submitted")}${set("approvedAt", "null")}${set("rejectedAt", "null")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;${openApproval}
  ${record("expense.reopened", "reopened an expense", { summary: sqlString("reopened an expense"), keys: "'reason', trim(reopen_expense.reason)" })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("reopen_expense")}(uuid, text)`)}

-- Takes a reimbursed expense back to approved, as a holder of the reimburse
-- key, with a reason the audit keeps. Otherwise reimbursed is final.
create or replace function ${fn("reverse_expense_reimbursement")}(expense_id uuid, reason text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${table}%rowtype;
begin${load("reverse_expense_reimbursement.expense_id")}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${e("tenant")}`, reimburse)}) then
    ${forbidden("not allowed to reverse a reimbursement")}
  end if;
  if nullif(trim(reverse_expense_reimbursement.reason), '') is null then
    ${invalid("reversing a reimbursement needs a reason")}
  end if;
  if ${status("v_row")} = 'approved' then
    ${conflict("EXPENSE_NOT_REIMBURSED", "this expense is not reimbursed")}
  end if;
  if ${status("v_row")} <> 'reimbursed' then
    ${conflict("EXPENSE_LOCKED", "only a reimbursed expense has a reimbursement to reverse")}
  end if;
  update ${table} x set ${e("reimbursedAt")} = null${setStatus("approved")}${set("reimbursement", "null")}, ${e("updatedAt")} = now()
    where x.${e("id")} = v_row.${e("id")}
    returning * into v_row;
  ${record("expense.reimbursement_reversed", "reversed the reimbursement of an expense", { summary: sqlString("reversed the reimbursement of an expense"), keys: "'reason', trim(reverse_expense_reimbursement.reason)" })}
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("reverse_expense_reimbursement")}(uuid, text)`)}

-- The expenses of expense_ids the caller decides as owner or creator, in one
-- read for a list: expense_self_decides for each id.
create or replace function ${fn("expense_self_decides_many")}(expense_ids uuid[])
returns uuid[]
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(array_agg(v_row.${e("id")}), '{}'::uuid[])
  from ${table} v_row
  where v_row.${e("id")} = any (expense_self_decides_many.expense_ids)
    and auth.uid() is not null
    and ${selfOf("v_row", "auth.uid()")} and ${decides("v_row")} and ${nobodyElse("v_row", creatorOf("v_row"))}
$$;
${userGrant(`${fn("expense_self_decides_many")}(uuid[])`)}

-- Whether the caller decides this expense as its owner or creator: they may
-- decide it and nobody else can. Apps show the rule with it.
create or replace function ${fn("expense_self_decides")}(expense_id uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select cardinality(${fn("expense_self_decides_many")}(array[expense_self_decides.expense_id])) > 0
$$;
${userGrant(`${fn("expense_self_decides")}(uuid)`)}

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

-- Expenses as a keyset page, newest spend first: the caller's, or everyone's
-- with expenses.read unless filters.mine is true (ADR 1077). filters is
-- { userId, status, currency, categoryId (each a value or a list), mine
-- (["true"]), search (description, merchant), sort (spentOn, amount,
-- createdAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function ${fn("page_expenses")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_expenses.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  v_reader boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "page_expenses.tenant", read)};
  ${listDeclare(expensePage)}
begin
  if not (v_reader or ${ctx.can("tenant", "page_expenses.tenant", submit)}) then
    ${forbidden("not allowed to list expenses")}
  end if;
  ${listBody(expensePage)}
end;
$$;
${userGrant(`${fn("page_expenses")}(${idType}, jsonb)`)}
`;
}

/**
 * Version 1 to 2: an expense without a creator gets its owner's user, so rows
 * from before the creator stamp (ADR 1091) don't fail closed. An owner without
 * a user leaves the creator null.
 */
export const EXPENSE_CREATOR_BACKFILL: BlockSqlUpgrade = {
  from: 1,
  description:
    "Expenses without a creator get their owner's user as created_by (ADR 1091).",
  sql: (ctx) => {
    if (!expensesStandalone(ctx) || !ctx.has("expenses", "createdBy")) {
      return "";
    }

    const owner = recordOwner(ctx, {
      block: "expenses",
      table: "expenses",
      noun: "expense",
      helper: "expense_is_mine",
    }).requester("x");

    const creator = ctx.col("expenses", "createdBy");

    return `update ${ctx.table("expenses")} x set ${creator} = ${owner}
  where x.${creator} is null and ${owner} is not null;`;
  },
};
