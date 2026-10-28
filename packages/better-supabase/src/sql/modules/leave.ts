import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";
import type { BlockContributes } from "../contributions.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { employeeKeyBackfillSql, employeeKeySql } from "../employee-key-sql.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { leaveBalanceFunctions, unpostTaken } from "./leave-balances.ts";
import {
  leaveEndPart,
  leaveFeed,
  leaveFeedSubject,
  leavePartial,
  leaveStartPart,
  leaveTypeKey,
} from "./leave-feed.ts";
import { leaveLedgerFunctions, leaveLedgerUpgrade } from "./leave-ledger.ts";
import { LEAVE_NAMES } from "./leave-names.ts";
import {
  dropSignatures,
  halfDays,
  leaveBalancesTable,
  leaveByEmployee,
  leaveOwner,
  leaveParts,
  leavePartsMapped,
} from "./leave-owner.ts";
import { appUniqueIndex, lockModuleTable } from "./over-app.ts";
import { OPERATIONS, moduleOperations } from "./permissions-model.ts";

/** Leave requests this block files with approvals. */
const LEAVE_REQUEST_SUBJECT = "leave_request";

const WHERE = "blocks.leave.options";

/** The keys the request reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

const DAYS = ["mon", "tue", "wed", "thu", "fri", "sat", "sun"] as const;

const ISO_WEEKDAY = new Map<string, number>(
  DAYS.map((day, index) => [day, index + 1]),
);

/** `options.workingDays` as ISO weekday numbers (Monday is 1). */
function workingDaysOf(ctx: BlockSqlContext): readonly number[] {
  const days = ctx.list("workingDays", ["mon", "tue", "wed", "thu", "fri"]);

  if (days.length === 0) {
    throw new TypeError(`${WHERE}.workingDays must name at least one day`);
  }

  return [
    ...new Set(
      days.map((day) => {
        const weekday = ISO_WEEKDAY.get(day);

        if (weekday === undefined) {
          throw new TypeError(
            `${WHERE}.workingDays: "${day}" is not one of ${DAYS.join(", ")}`,
          );
        }

        return weekday;
      }),
    ),
  ].toSorted((a, b) => a - b);
}

/** `options.policy` as an approvals policy; defaults to one approver step. */
function leavePolicy(ctx: BlockSqlContext): string {
  const raw = ctx.option("policy") ?? {
    steps: [
      {
        approvers: {
          permission: ctx.permissionKey("approve", OPERATIONS["leave.approve"]),
        },
      },
    ],
  };

  const policy = policyOf(
    LEAVE_REQUEST_SUBJECT,
    "approve",
    raw,
    `${WHERE}.policy`,
  );

  if (policy.run !== undefined) {
    throw new TypeError(
      `${WHERE}.policy.run is not allowed; the final approval books the leave`,
    );
  }

  return policySnapshot(policy);
}

/**
 * Whether requests keep their decision themselves instead of in the approvals
 * block: `options.approvals: false`, or no approval column.
 */
function leaveStatusMode(ctx: BlockSqlContext): boolean {
  return !ctx.flag("approvals", true) || !ctx.has("requests", "approval");
}

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  // options.approvals: false keeps the decision on the request: the app or
  // a member with the approve permission decides it with decide_leave_request.
  const statusMode = leaveStatusMode(ctx);
  const approvals = statusMode ? undefined : ctx.of("approvals");
  const rejections = statusMode && ctx.has("requests", "rejectedAt");

  if (approvals?.mode === "custom") {
    throw new TypeError(
      "blocks.leave needs the approvals tables; approvals can't be in custom mode",
    );
  }

  const owner = leaveOwner(ctx);
  const parts = leaveParts(ctx);
  const appBalances = leaveBalancesTable(ctx);
  const me = owner.variable;
  const types = ctx.table("types");
  const requests = ctx.table("requests");
  const ty = (column: string): string => ctx.col("types", column);
  const q = (column: string): string => ctx.col("requests", column);
  const ar = approvals?.table("requests") ?? "";

  const a = (column: string): string =>
    approvals?.col("requests", column) ?? "";

  // Joins a request alias to its approval request as `approval`.
  const joinApproval = (alias: string, approval: string): string =>
    approvals === undefined
      ? ""
      : `\n    left join ${ar} ${approval} on ${approval}.${a("id")} = ${alias}.${q("approval")}`;

  const approvalVar =
    approvals === undefined ? "" : `\n  v_approval ${ar}%rowtype;`;

  const loadApproval =
    approvals === undefined
      ? ""
      : `\n  select * into v_approval from ${ar} x where x.${a("id")} = v_row.${q("approval")};`;

  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("leave");
  const request = ctx.permission("request", permissions.request);
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const policy = leavePolicy(ctx);
  const working = `array[${workingDaysOf(ctx).join(", ")}]`;
  const allowNegative = ctx.flag("allowNegative", false);
  const idType = ctx.idType;
  const extras = ctx.extraColumns("requests", RESERVED);
  const extra = extraFieldsArg(extras);

  const forbidden = (message: string): string =>
    fail("LEAVE_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("LEAVE_INVALID", message, "22023");

  // A column of row, or null when the app maps it to null.
  const or = (table: string, row: string, logical: string): string =>
    ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : "null";

  // ", <column>" for an insert's column list, when the column exists.
  const also = (table: string, logical: string): string =>
    ctx.has(table, logical) ? `, ${ctx.col(table, logical)}` : "";

  // ", <value>" matching also().
  const alsoValue = (table: string, logical: string, value: string): string =>
    ctx.has(table, logical) ? `, ${value}` : "";

  // A column definition, left out when the app maps the column to null.
  const column = (
    table: string,
    logical: string,
    definition: (name: string) => string,
  ): string =>
    ctx.has(table, logical)
      ? `\n  ${definition(ctx.col(table, logical))},`
      : "";

  // Refuses a non-null argument the types table has no column for.
  const typeUnsupported = (
    logical: string,
    arg: string,
    thing: string,
  ): string =>
    ctx.has("types", logical)
      ? ""
      : `
  if ${arg} is not null then
    ${fail(`LEAVE_${thing.toUpperCase().replaceAll(" ", "_")}_UNSUPPORTED`, `this leave types table has no ${thing} column`, "22023")}
  end if;`;

  // The type's columns save_leave_type writes, with their arguments.
  const typeSettings = (
    [
      ["allowance", "save_leave_type.allowance"],
      ["carryoverMax", "save_leave_type.carryover_max"],
      ["color", "save_leave_type.color"],
    ] as const
  ).filter(([logical]) => ctx.has("types", logical));

  // The upsert's third line of the type's settings, after allowance.
  const settingsLine = typeSettings
    .filter(([logical]) => logical !== "allowance")
    .map(([logical]) => `${ty(logical)} = excluded.${ty(logical)}`)
    .join(", ");

  const unitArg = ctx.cast(
    "types",
    "unit",
    "coalesce(save_leave_type.unit, 'days')",
  );

  // save_leave_type's write: an upsert by key, or by id without a key column.
  const typeUpsert = ctx.has("types", "key")
    ? `  insert into ${types} (${ty("tenant")}, ${ty("key")}, ${ty("name")}, ${ty("unit")}, ${ty("paid")}, ${ty("tracked")}${typeSettings.map(([logical]) => `, ${ty(logical)}`).join("")})
  values (save_leave_type.tenant, save_leave_type.key, save_leave_type.name, ${unitArg}, coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true)${typeSettings.map(([, arg]) => `, ${arg}`).join("")})
  on conflict (${ty("tenant")}, ${ty("key")}) do update
    set ${ty("name")} = excluded.${ty("name")}, ${ty("unit")} = excluded.${ty("unit")}, ${ty("paid")} = excluded.${ty("paid")},
      ${ty("tracked")} = excluded.${ty("tracked")}${ctx.has("types", "allowance") ? `, ${ty("allowance")} = excluded.${ty("allowance")}` : ""},
      ${settingsLine === "" ? "" : `${settingsLine},\n      `}${ty("archivedAt")} = null, ${ty("updatedAt")} = now()
  returning * into v_row;`
    : `  select * into v_row from ${types} x
    where x.${ty("tenant")} = save_leave_type.tenant and x.${ty("id")}::text = save_leave_type.key
    for update;
  if found then
    update ${types} x
      set ${ty("name")} = save_leave_type.name, ${ty("unit")} = ${unitArg}, ${ty("paid")} = coalesce(save_leave_type.paid, true),
        ${ty("tracked")} = coalesce(save_leave_type.tracked, true)${typeSettings.map(([logical, arg]) => `, ${ty(logical)} = ${arg}`).join("")}, ${ty("archivedAt")} = null, ${ty("updatedAt")} = now()
      where x.${ty("id")} = v_row.${ty("id")}
      returning * into v_row;
  else
    insert into ${types} (${ty("tenant")}, ${ty("name")}, ${ty("unit")}, ${ty("paid")}, ${ty("tracked")}${typeSettings.map(([logical]) => `, ${ty(logical)}`).join("")})
    values (save_leave_type.tenant, save_leave_type.name, ${unitArg}, coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true)${typeSettings.map(([, arg]) => `, ${arg}`).join("")})
    returning * into v_row;
  end if;`;

  const status = (row: string, approval: string): string =>
    approvals === undefined
      ? `case when ${row}.${q("cancelledAt")} is not null then 'cancelled' when ${row}.${q("approvedAt")} is not null then 'approved'${rejections ? ` when ${row}.${q("rejectedAt")} is not null then 'rejected'` : ""} else 'pending' end`
      : `case when ${row}.${q("cancelledAt")} is not null then 'cancelled' when ${row}.${q("approvedAt")} is not null then 'approved' when ${approval}.${a("status")} in ('rejected', 'expired') then 'rejected' when ${approval}.${a("status")} = 'cancelled' then 'cancelled' else 'pending' end`;

  const typeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${ty("id")}, 'organizationId', ${row}.${ty("tenant")}, 'key', ${leaveTypeKey(ctx, row)}, 'name', ${row}.${ty("name")}, 'unit', ${row}.${ty("unit")}, 'paid', ${row}.${ty("paid")}, 'tracked', ${row}.${ty("tracked")}, 'allowance', ${or("types", row, "allowance")}::text, 'carryoverMax', ${or("types", row, "carryoverMax")}::text, 'color', ${or("types", row, "color")}, 'archivedAt', ${row}.${ty("archivedAt")}, 'createdAt', ${row}.${ty("createdAt")}, 'updatedAt', ${row}.${ty("updatedAt")})`;

  const requestJson = (row: string, approval: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}, 'userId', ${or("requests", row, "user")}${owner.json(row)}, 'typeId', ${row}.${q("type")}, 'startsOn', ${row}.${q("startsOn")}, 'endsOn', ${row}.${q("endsOn")}, 'partial', ${leavePartial(ctx, row)}${parts ? `, 'startPart', ${leaveStartPart(ctx, row)}, 'endPart', ${leaveEndPart(ctx, row)}` : ""}, 'amount', ${row}.${q("amount")}::text, 'note', ${or("requests", row, "note")}, 'status', ${status(row, approval)}, 'approvalId', ${or("requests", row, "approval")}, 'approvedAt', ${row}.${q("approvedAt")}, 'cancelledAt', ${row}.${q("cancelledAt")}, 'createdAt', ${row}.${q("createdAt")}, 'updatedAt', ${row}.${q("updatedAt")}${extraFieldsJson(row, extras)})`;

  const requestRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${q("tenant")}, 'id', ${row}.${q("id")}, 'userId', ${or("requests", row, "user")}${owner.json(row)}, 'typeId', ${row}.${q("type")}, 'startsOn', ${row}.${q("startsOn")}, 'endsOn', ${row}.${q("endsOn")}, 'amount', ${row}.${q("amount")}::text, 'approvalId', ${or("requests", row, "approval")})`,
      subject: `'leave-requests/' || ${row}.${q("id")}::text`,
      tenant: `${row}.${q("tenant")}`,
      audit: {
        category: "data",
        targetType: "leave_request",
        recordId: `${row}.${q("id")}::text`,
        summary: `${sqlString(summary)} || ' from ' || ${row}.${q("startsOn")}::text || ' to ' || ${row}.${q("endsOn")}::text`,
      },
    });

  const period = (row: string): string =>
    `extract(year from ${row}.${q("startsOn")})::integer`;

  const pendingIn = (alias: string, approval: string): string =>
    approvals === undefined
      ? `${alias}.${q("cancelledAt")} is null and ${alias}.${q("approvedAt")} is null${rejections ? ` and ${alias}.${q("rejectedAt")} is null` : ""}`
      : `${alias}.${q("cancelledAt")} is null and ${alias}.${q("approvedAt")} is null and ${approval}.${a("status")} = 'pending'`;

  const approvalRow = approvals === undefined ? "" : "v_approval";
  const approve = ctx.permission("approve", permissions.approve);

  const decision = (column: string, value: string): string =>
    ctx.has("requests", column) ? `, ${q(column)} = ${value}` : "";

  const decide = `
-- Approves or rejects a pending request without the approvals block: the
-- service role, or a member with the approve permission who didn't ask for
-- it. Approval books the leave like a final approval.
create or replace function ${fn("decide_leave_request")}(request_id uuid, approved boolean, note text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${requests}%rowtype;
begin
  select * into v_row from ${requests} x where x.${q("id")} = decide_leave_request.request_id for update;
  if not found then
    ${fail("LEAVE_REQUEST_NOT_FOUND", "leave request not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or (${ctx.can("tenant", `v_row.${q("tenant")}`, approve)} and ${owner.requester("v_row")} is distinct from auth.uid())) then
    ${forbidden("not allowed to decide this leave request")}
  end if;
  if not (${pendingIn("v_row", "")}) then
    ${fail("LEAVE_REQUEST_CLOSED", "this leave request was already decided or cancelled", "55000")}
  end if;
  if decide_leave_request.approved is null then
    ${invalid("approved must be true or false")}
  end if;
  if decide_leave_request.approved then
    perform ${fn("approve_leave_request")}(v_row.${q("id")});
    update ${requests} x set ${q("updatedAt")} = now()${decision("decidedBy", "auth.uid()")}${decision("decisionNote", "nullif(trim(decide_leave_request.note), '')")}
      where x.${q("id")} = v_row.${q("id")}
      returning * into v_row;
  else${
    rejections
      ? `
    update ${requests} x set ${q("rejectedAt")} = now(), ${q("updatedAt")} = now()${decision("decidedBy", "auth.uid()")}${decision("decisionNote", "nullif(trim(decide_leave_request.note), '')")}
      where x.${q("id")} = v_row.${q("id")}
      returning * into v_row;
    ${requestRecord("leave.rejected", "v_row", "rejected leave")}`
      : `
    ${fail("LEAVE_REJECTION_UNSUPPORTED", "this leave requests table has no rejected_at column", "22023")}`
  }
  end if;
  return ${requestJson("v_row", "")};
end;
$$;
${userGrant(`${fn("decide_leave_request")}(uuid, boolean, text)`)}
`;

  const balanceCheck = allowNegative
    ? ""
    : `
  if v_type.${ty("tracked")} and ${fn("leave_available")}(request_leave.tenant, ${me}, v_type.${ty("id")}, ${appBalances ? "request_leave.starts_on" : "extract(year from request_leave.starts_on)::integer"}) < v_amount then
    ${fail("LEAVE_BALANCE_EXCEEDED", "this request is more than the available balance", "23514")}
  end if;`;

  const tables = ctx.manages
    ? `create table if not exists ${types} (
  ${ty("id")} uuid primary key default gen_random_uuid(),
  ${ty("tenant")} ${idType} not null,
${column("types", "key", (name) => `${name} text not null check (${name} ~ '^[a-z][a-z0-9_-]{0,62}$')`).slice(1)}
  ${ty("name")} text not null check (length(${ty("name")}) between 1 and 100),
  ${ty("unit")} text not null default 'days' check (${ty("unit")} in ('days', 'hours')),
  ${ty("paid")} boolean not null default true,
  -- Untracked types (unpaid leave, say) book no ledger entries and skip the balance check.
  ${ty("tracked")} boolean not null default true,${ctx.has("types", "allowance") ? `\n  -- What accrue_leave grants each member per period when it names no amount.` : ""}${column("types", "allowance", (name) => `${name} numeric(8, 2) check (${name} is null or ${name} >= 0)`)}${ctx.has("types", "carryoverMax") ? `\n  -- How much close_leave_year carries into the next period; null carries everything.` : ""}${column("types", "carryoverMax", (name) => `${name} numeric(8, 2) check (${name} is null or ${name} >= 0)`)}${column("types", "color", (name) => `${name} text check (${name} is null or ${name} ~ '^#[0-9a-fA-F]{6}$')`)}
  ${ty("archivedAt")} timestamptz,
  ${ty("createdAt")} timestamptz not null default now(),
  ${ty("updatedAt")} timestamptz not null default now(),
${
  ctx.has("types", "key")
    ? `  unique (${ty("tenant")}, ${ty("key")}),
`
    : ""
}  unique (${ty("tenant")}, ${ty("id")})
);${ctx.has("types", "key") ? appUniqueIndex(ctx, "types", ["tenant", "key"]) : ""}${appUniqueIndex(ctx, "types", ["tenant", "id"])}
${lockModuleTable(ctx, "types", { read: true })}
${renderPolicy(makePolicy({ table: types, name: ctx.naming.rename("leave_types_read"), command: "select", roles: ["authenticated"], using: `${ctx.scope.check(ty("tenant"), request)} or ${ctx.scope.check(ty("tenant"), read)}` }), { drop: true, target: types })}

create table if not exists ${requests} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${idType} not null,
  ${owner.employee ? `${ctx.has("requests", "user") ? `${q("user")} uuid,\n  ` : ""}${q("employee")} uuid not null` : `${q("user")} uuid not null`},
  ${q("type")} uuid not null,
  ${q("startsOn")} date not null,
  ${q("endsOn")} date not null,
${column("requests", "partial", (name) => `${name} text not null default 'full' check (${name} in ('full', 'morning', 'afternoon', 'hours'))`).slice(1)}
  -- Working days, or hours for an hours type, that the request books.
  ${q("amount")} numeric(8, 2) not null check (${q("amount")} > 0),${column("requests", "note", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}
${approvals === undefined ? "" : `  ${q("approval")} uuid references ${ar} (${a("id")}) on delete set null,\n`}  ${q("approvedAt")} timestamptz,${statusMode ? `${column("requests", "rejectedAt", (name) => `${name} timestamptz`)}${column("requests", "decidedBy", (name) => `${name} uuid`)}${column("requests", "decisionNote", (name) => `${name} text check (${name} is null or length(${name}) <= 2000)`)}` : ""}
  ${q("cancelledAt")} timestamptz,${column("requests", "cancelledBy", (name) => `${name} uuid`)}
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  check (${q("endsOn")} >= ${q("startsOn")}),
  foreign key (${q("tenant")}, ${q("type")}) references ${types} (${ty("tenant")}, ${ty("id")}) on delete restrict
);${addExtraColumns(requests, extras)}
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_user_idx`)} on ${requests} (${q("tenant")}, ${owner.column}, ${q("startsOn")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_dates_idx`)} on ${requests} (${q("tenant")}, ${q("startsOn")}, ${q("endsOn")});
${approvals === undefined ? "" : `create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_approval_idx`)} on ${requests} (${q("approval")}) where ${q("approval")} is not null;\n`}create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_type_idx`)} on ${requests} (${q("tenant")}, ${q("type")});
${lockModuleTable(ctx, "requests", { read: true })}
${renderPolicy(makePolicy({ table: requests, name: ctx.naming.rename("leave_requests_read"), command: "select", roles: ["authenticated"], using: `${owner.mine} or ${ctx.scope.check(q("tenant"), read)}` }), { drop: true, target: requests })}

`
    : "";

  const pending = (
    tenant: string,
    user: string,
    type: string,
    year: string,
  ): string =>
    `coalesce((select sum(r.${q("amount")}) from ${requests} r${joinApproval("r", "p").replace("\n    ", "\n      ")}
      where r.${q("tenant")} = ${tenant} and r.${owner.column} = ${user}
        and r.${q("type")} = ${type} and ${period("r")} = ${year}
        and ${pendingIn("r", "p")}), 0)`;

  const requestBase = `${idType}, uuid, date, date, text, numeric, text`;
  const listBase = `${idType}, uuid, text, date, date, boolean, integer`;
  const requestTypes = `${requestBase}${parts ? ", text, text" : ""}${owner.employee ? ", uuid" : ""}`;
  const requestParams = `${parts ? ", start_part text default null, end_part text default null" : ""}${owner.employee ? ", employee_id uuid default null" : ""}`;

  const ownerColumns = owner.employee
    ? `${ctx.has("requests", "user") ? `${q("user")}, ` : ""}${q("employee")}`
    : q("user");

  const ownerValues = owner.employee
    ? `${ctx.has("requests", "user") ? "v_user, " : ""}v_owner`
    : "v_me";

  const existing = halfDays(
    `r.${q("startsOn")}`,
    `r.${q("endsOn")}`,
    leaveStartPart(ctx, "r"),
    leaveEndPart(ctx, "r"),
  );

  const asked = halfDays(
    "request_leave.starts_on",
    "request_leave.ends_on",
    "v_start",
    "v_end",
  );

  const employeeKey =
    ctx.installed("employees") && !owner.employee
      ? employeeKeySql(ctx.of("employees"), { owner: ctx, table: "requests" })
      : "";

  return `${schemaPreamble(ctx)}
${owner.helper}${tables}${employeeKey}${appBalances ? leaveBalanceFunctions(ctx, { owner, pending }) : leaveLedgerFunctions(ctx, { owner, pending })}
-- The working days (options.workingDays) from one date to another, inclusive.
create or replace function ${fn("leave_working_days")}(starts_on date, ends_on date)
returns integer
language sql
immutable
set search_path = ''
as $$
  select count(*)::integer
  from generate_series(leave_working_days.starts_on, leave_working_days.ends_on, interval '1 day') d
  where extract(isodow from d)::integer = any (${working})
$$;
${userGrant(`${fn("leave_working_days")}(date, date)`)}

-- Creates or updates a leave type by key. Without a key column, key is the
-- id of the type to update, and any other key creates one.
create or replace function ${fn("save_leave_type")}(tenant ${idType}, key text, name text, unit text default 'days', paid boolean default true, tracked boolean default true, allowance numeric default null, carryover_max numeric default null, color text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_row ${types}%rowtype;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "save_leave_type.tenant", manage)}) then
    ${forbidden("not allowed to manage leave types")}
  end if;${typeUnsupported("allowance", "save_leave_type.allowance", "allowance")}${typeUnsupported("carryoverMax", "save_leave_type.carryover_max", "carryover")}${typeUnsupported("color", "save_leave_type.color", "color")}
${typeUpsert}
  return ${typeJson("v_row")};
end;
$$;
${userGrant(`${fn("save_leave_type")}(${idType}, text, text, text, boolean, boolean, numeric, numeric, text)`)}

-- Hides a type from new requests; its requests and ledger stay.
create or replace function ${fn("archive_leave_type")}(type_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${types}%rowtype;
begin
  select * into v_row from ${types} x where x.${ty("id")} = archive_leave_type.type_id for update;
  if not found then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${ty("tenant")}`, manage)}) then
    ${forbidden("not allowed to manage leave types")}
  end if;
  update ${types} x set ${ty("archivedAt")} = coalesce(x.${ty("archivedAt")}, now()), ${ty("updatedAt")} = now()
    where x.${ty("id")} = v_row.${ty("id")}
    returning * into v_row;
  return ${typeJson("v_row")};
end;
$$;
${userGrant(`${fn("archive_leave_type")}(uuid)`)}

create or replace function ${fn("list_leave_types")}(tenant ${idType}, archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${typeJson("x")} order by x.${ty("name")}), '[]'::jsonb)
  from ${types} x
  where x.${ty("tenant")} = list_leave_types.tenant
    and (coalesce(list_leave_types.archived, false) or x.${ty("archivedAt")} is null)
$$;
${userGrant(`${fn("list_leave_types")}(${idType}, boolean)`)}

-- Asks for leave and opens its approval. A day type books working days
-- (half a day for a morning or afternoon); an hours type books hours.
-- Without options.allowNegative the request can't exceed the balance of
-- the period it starts in. fields: the extra columns to set.
${requestTypes === requestBase ? "" : `${dropSignatures(fn("request_leave"), requestBase)}\n`}${extra.drop(fn("request_leave"), requestTypes)}
create or replace function ${fn("request_leave")}(tenant ${idType}, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null${requestParams}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_type ${types}%rowtype;
  v_partial text := coalesce(request_leave.partial, 'full');${parts ? "\n  v_start text;\n  v_end text;" : ""}${owner.declare}
  v_amount numeric;
  v_row ${requests}%rowtype;${approvalVar}${approvals === undefined ? "" : "\n  v_request jsonb;"}
begin
${
  owner.employee
    ? `  ${owner.resolve("request_leave.tenant", "null", "request_leave.employee_id")}
  if v_owner is null then
    ${fail("LEAVE_EMPLOYEE_INVALID", "no employee record for that member in this organization", "22023")}
  end if;
  if v_me is not null and v_user = v_me then
    if not ${ctx.can("tenant", "request_leave.tenant", request)} then
      ${forbidden("not allowed to request leave here")}
    end if;
  elsif not (${SERVICE_CALLER} or ${ctx.can("tenant", "request_leave.tenant", manage)} or ${owner.manages("request_leave.tenant", "v_owner")}) then
    ${forbidden("not allowed to request leave for another employee")}
  end if;`
    : `  if v_me is null or not ${ctx.can("tenant", "request_leave.tenant", request)} then
    ${forbidden("not allowed to request leave here")}
  end if;`
}
  select * into v_type from ${types} x
    where x.${ty("id")} = request_leave.type_id and x.${ty("tenant")} = request_leave.tenant and x.${ty("archivedAt")} is null;
  if not found then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  if request_leave.starts_on is null or request_leave.ends_on is null or request_leave.ends_on < request_leave.starts_on then
    ${invalid("ends_on must be on or after starts_on")}
  end if;
${
  parts
    ? `  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    ${invalid("partial must be full, morning, afternoon or hours")}
  end if;
  v_start := coalesce(request_leave.start_part, case v_partial when 'afternoon' then 'afternoon' when 'hours' then 'hours' else 'full' end);
  v_end := coalesce(request_leave.end_part, case v_partial when 'morning' then 'morning' when 'hours' then 'hours' else 'full' end);
  if v_start not in ('full', 'morning', 'afternoon', 'hours') or v_end not in ('full', 'morning', 'afternoon', 'hours') then
    ${invalid("start_part and end_part must be full, morning, afternoon or hours")}
  end if;
  if (v_start = 'hours' or v_end = 'hours') and (v_start <> v_end or request_leave.starts_on <> request_leave.ends_on) then
    ${invalid("a request in hours starts and ends in hours on the same date")}
  end if;
  if request_leave.starts_on = request_leave.ends_on and v_start = 'afternoon' and v_end = 'morning' then
    ${invalid("a single day can't start in the afternoon and end in the morning")}
  end if;
  if v_type.${ty("unit")} = 'hours' then
    if request_leave.hours is null or request_leave.hours <= 0 then
      ${invalid("an hours type needs hours greater than zero")}
    end if;
    v_amount := request_leave.hours;
  else
    if v_start = 'hours' then
      ${invalid("a day type takes parts full, morning or afternoon")}
    end if;
    v_amount := ${fn("leave_working_days")}(request_leave.starts_on, request_leave.ends_on)
      - case when v_start = 'afternoon' and ${fn("leave_working_days")}(request_leave.starts_on, request_leave.starts_on) = 1 then 0.5 else 0 end
      - case when v_end = 'morning' and ${fn("leave_working_days")}(request_leave.ends_on, request_leave.ends_on) = 1 then 0.5 else 0 end;
  end if;
  v_partial := case when v_start = 'hours' then 'hours'
    when request_leave.starts_on = request_leave.ends_on and v_start = 'afternoon' then 'afternoon'
    when request_leave.starts_on = request_leave.ends_on and v_end = 'morning' then 'morning'
    else 'full' end;`
    : `  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
    ${invalid("partial must be full, morning, afternoon or hours")}
  end if;
  if v_type.${ty("unit")} = 'hours' then
    if v_partial <> 'hours' and v_partial <> 'full' then
      ${invalid("an hours type takes partial hours")}
    end if;
    if request_leave.hours is null or request_leave.hours <= 0 then
      ${invalid("an hours type needs hours greater than zero")}
    end if;
    v_partial := 'hours';
    v_amount := request_leave.hours;
  else
    if v_partial = 'hours' then
      ${invalid("a day type takes partial full, morning or afternoon")}
    end if;
    if v_partial in ('morning', 'afternoon') and request_leave.starts_on <> request_leave.ends_on then
      ${invalid("a half day starts and ends on the same date")}
    end if;${
      ctx.has("requests", "partial")
        ? ""
        : `
    if v_partial <> 'full' then
      ${fail("LEAVE_PARTIAL_UNSUPPORTED", "this leave requests table has no partial column, so a request takes whole days", "22023")}
    end if;`
    }
    v_amount := ${fn("leave_working_days")}(request_leave.starts_on, request_leave.ends_on)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;`
}
  if v_amount <= 0 then
    ${invalid("the request covers no working days")}
  end if;${
    ctx.has("requests", "note")
      ? ""
      : `
  if nullif(trim(request_leave.note), '') is not null then
    ${fail("LEAVE_NOTE_UNSUPPORTED", "this leave requests table has no note column", "22023")}
  end if;`
  }
  perform pg_advisory_xact_lock(hashtextextended('leave:' || request_leave.tenant::text || ':' || ${me}::text, 0));
  if exists (
    select 1 from ${requests} r${joinApproval("r", "p")}
    where r.${q("tenant")} = request_leave.tenant and r.${owner.column} = ${me}
      and r.${q("cancelledAt")} is null and (r.${q("approvedAt")} is not null or ${approvals === undefined ? `(${pendingIn("r", "p")})` : `p.${a("status")} = 'pending'`})
${
  parts
    ? `      and ${existing.first} <= ${asked.last} and ${asked.first} <= ${existing.last}
`
    : `      and daterange(r.${q("startsOn")}, r.${q("endsOn")}, '[]') && daterange(request_leave.starts_on, request_leave.ends_on, '[]')
`
}${
    !parts && ctx.has("requests", "partial")
      ? `      and not (r.${q("partial")} = 'morning' and v_partial = 'afternoon')
      and not (r.${q("partial")} = 'afternoon' and v_partial = 'morning')
`
      : ""
  }  ) then
    ${fail("LEAVE_OVERLAP", "this overlaps another leave request", "23P01")}
  end if;${balanceCheck}
  ${ctx.hook("before_leave_request", [
    [idType, "request_leave.tenant"],
    ["uuid", `v_type.${ty("id")}`],
    ["date", "request_leave.starts_on"],
    ["date", "request_leave.ends_on"],
    ["numeric", "v_amount"],
  ])}
  insert into ${requests} (${q("tenant")}, ${ownerColumns}, ${q("type")}, ${q("startsOn")}, ${q("endsOn")}${also("requests", "partial")}${parts ? `, ${q("startPart")}, ${q("endPart")}` : ""}, ${q("amount")}${also("requests", "note")})
  values (request_leave.tenant, ${ownerValues}, v_type.${ty("id")}, request_leave.starts_on, request_leave.ends_on${ctx.has("requests", "partial") ? `, ${ctx.cast("requests", "partial", "v_partial")}` : ""}${parts ? `, ${ctx.cast("requests", "startPart", "v_start")}, ${ctx.cast("requests", "endPart", "v_end")}` : ""}, v_amount${alsoValue("requests", "note", "nullif(trim(request_leave.note), '')")})
  returning * into v_row;${writeExtraColumns(requests, extras, "request_leave.fields", `x.${q("id")} = v_row.${q("id")}`, "v_row")}${
    approvals === undefined
      ? ""
      : `
  v_request := ${approvals.fn("open_approval")}(
    request_leave.tenant, ${sqlString(LEAVE_REQUEST_SUBJECT)}, v_row.${q("id")}::text, 'approve',
    ${sqlString(policy)}::jsonb, ${or("requests", "v_row", "note")},
    jsonb_build_object('userId', ${owner.employee ? "v_user, 'employeeId', v_owner" : "v_me"}, 'typeId', v_type.${ty("id")}, 'type', v_type.${ty("name")}, 'startsOn', v_row.${q("startsOn")}, 'endsOn', v_row.${q("endsOn")}, 'amount', v_amount::text, 'unit', v_type.${ty("unit")})
  );
  update ${requests} x set ${q("approval")} = (v_request ->> 'id')::uuid
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;${loadApproval}`
  }
  ${requestRecord("leave.requested", "v_row", "requested leave")}
  ${ctx.hook("after_leave_request", [["uuid", `v_row.${q("id")}`]])}
  return ${requestJson("v_row", approvalRow)};
end;
$$;
${userGrant(`${fn("request_leave")}(${requestTypes}${extra.type})`)}

-- Books the leave once the approval is final: approved_at and, for a
-- tracked type, a taken entry. Approvals calls it; it isn't granted to anyone.
create or replace function ${fn("approve_leave_request")}(request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${requests}%rowtype;
begin
  update ${requests} x set ${q("approvedAt")} = now(), ${q("updatedAt")} = now()
    where x.${q("id")} = approve_leave_request.request_id and x.${q("approvedAt")} is null and x.${q("cancelledAt")} is null
    returning * into v_row;
  if not found then
    return;
  end if;
  perform ${fn("leave_post")}(v_row.${q("tenant")}, v_row.${owner.column}, v_row.${q("type")}, 'taken', -v_row.${q("amount")}, ${period("v_row")}, v_row.${q("id")})
  from ${types} t where t.${ty("id")} = v_row.${q("type")} and t.${ty("tracked")};
  ${requestRecord("leave.approved", "v_row", "approved leave")}
end;
$$;
revoke execute on function ${fn("approve_leave_request")}(uuid) from public, anon, authenticated;

-- Cancels a request: the requester before it starts, or a manager any
-- time. A pending approval is cancelled with it; approved leave goes back
-- to the balance.
create or replace function ${fn("cancel_leave_request")}(request_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${requests}%rowtype;${approvalVar}
  v_manager boolean;
begin
  select * into v_row from ${requests} x where x.${q("id")} = cancel_leave_request.request_id for update;
  if not found then
    ${fail("LEAVE_REQUEST_NOT_FOUND", "leave request not found", "P0002")}
  end if;
  v_manager := ${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${q("tenant")}`, manage)}${owner.employee ? ` or ${owner.manages(`v_row.${q("tenant")}`, `v_row.${q("employee")}`)}` : ""};
  if not (v_manager or coalesce(${owner.requester("v_row")} = auth.uid(), false)) then
    ${forbidden("not allowed to cancel this leave request")}
  end if;
  if v_row.${q("cancelledAt")} is not null then
    ${fail("LEAVE_REQUEST_CLOSED", "this leave request is already cancelled", "55000")}
  end if;
  if not v_manager and v_row.${q("approvedAt")} is not null and v_row.${q("startsOn")} <= current_date then
    ${forbidden("leave that has started can only be cancelled by a manager")}
  end if;
${
  approvals === undefined
    ? ""
    : `  update ${ar} p set ${a("status")} = 'cancelled', ${a("decidedAt")} = now()
    where p.${a("id")} = v_row.${q("approval")} and p.${a("status")} = 'pending';
`
}  if v_row.${q("approvedAt")} is not null then
    ${
      appBalances
        ? unpostTaken(ctx, `v_row.${q("id")}`)
        : `perform ${fn("leave_post")}(v_row.${q("tenant")}, v_row.${owner.column}, v_row.${q("type")}, 'taken', v_row.${q("amount")}, ${period("v_row")}, v_row.${q("id")}, 'cancelled')
    from ${types} t where t.${ty("id")} = v_row.${q("type")} and t.${ty("tracked")};`
    }
  end if;
  update ${requests} x set ${q("cancelledAt")} = now()${ctx.has("requests", "cancelledBy") ? `, ${q("cancelledBy")} = auth.uid()` : ""}, ${q("updatedAt")} = now()
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;${loadApproval}
  ${requestRecord("leave.cancelled", "v_row", "cancelled leave")}
  return ${requestJson("v_row", approvalRow)};
end;
$$;
${userGrant(`${fn("cancel_leave_request")}(uuid)`)}
${statusMode ? decide : ""}${leaveFeed(ctx)}
-- Requests that overlap a date range, earliest first: the caller's, or
-- everyone's with the read permission.
${owner.employee ? `drop function if exists ${fn("list_leave_requests")}(${listBase});\n` : ""}create or replace function ${fn("list_leave_requests")}(tenant ${idType}, user_id uuid default null, status text default null, starts date default null, ends date default null, everyone boolean default false, page_size integer default 100${owner.employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "list_leave_requests.tenant", read)};
  v_rows jsonb;${owner.declare}
begin
${
  owner.employee
    ? `  ${owner.resolve("list_leave_requests.tenant", "list_leave_requests.user_id", "list_leave_requests.employee_id")}
  if not v_reader and (coalesce(list_leave_requests.everyone, false)
    or not ((coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", "list_leave_requests.tenant", request)}) or ${owner.manages("list_leave_requests.tenant", "v_owner")})) then
    ${forbidden("not allowed to read this employee's leave")}
  end if;`
    : `  if not (v_reader or ${ctx.can("tenant", "list_leave_requests.tenant", request)}) then
    ${forbidden("not allowed to list leave requests")}
  end if;
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id is distinct from auth.uid())) then
    ${forbidden("not allowed to read another member's leave")}
  end if;`
}
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select ${requestJson("r", "p")} as item, r.${q("startsOn")} as starts, r.${q("createdAt")} as created
    from ${requests} r${joinApproval("r", "p")}
    where r.${q("tenant")} = list_leave_requests.tenant
      and ${
        owner.employee
          ? `(coalesce(list_leave_requests.everyone, false) or r.${q("employee")} = v_owner)`
          : `(case
        when coalesce(list_leave_requests.everyone, false) then true
        when list_leave_requests.user_id is not null then r.${q("user")} = list_leave_requests.user_id
        else r.${q("user")} = auth.uid()
      end)`
      }
      and (list_leave_requests.status is null or ${status("r", "p")} = list_leave_requests.status)
      and (list_leave_requests.starts is null or r.${q("endsOn")} >= list_leave_requests.starts)
      and (list_leave_requests.ends is null or r.${q("startsOn")} <= list_leave_requests.ends)
    order by r.${q("startsOn")}, r.${q("createdAt")}
    limit ${pageSize("list_leave_requests.page_size", 100, 500)}
  ) z;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_leave_requests")}(${listBase}${owner.employee ? ", uuid" : ""})`)}

`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("requests", RESERVED)).contract;
  const employee = leaveByEmployee(ctx) ? ["uuid"] : [];

  return [
    {
      name: "request_leave",
      args: [
        "{id}",
        "uuid",
        "date",
        "date",
        "text",
        "numeric",
        "text",
        ...(leavePartsMapped(ctx) ? ["text", "text"] : []),
        ...employee,
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "cancel_leave_request", args: ["uuid"], returns: "jsonb" },
    {
      name: "leave_balances",
      args: ["{id}", "uuid", "integer", ...employee],
      returns: "jsonb",
    },
    {
      name: "list_leave_requests",
      args: [
        "{id}",
        "uuid",
        "text",
        "date",
        "date",
        "boolean",
        "integer",
        ...employee,
      ],
      returns: "jsonb",
    },
    ...(leaveStatusMode(ctx)
      ? [
          {
            name: "decide_leave_request",
            args: ["uuid", "boolean", "text"],
            returns: "jsonb",
          },
        ]
      : []),
    ...(ctx.installed("share-links")
      ? [{ name: "leave_feed", args: ["text"], returns: "jsonb" }]
      : []),
  ];
}

const CONTRIBUTES: BlockContributes = {
  "share-links": (own) => [leaveFeedSubject(own)],
  approvals: (own) =>
    leaveStatusMode(own)
      ? []
      : [
          {
            subject: LEAVE_REQUEST_SUBJECT,
            access: "declared",
            approve: ({ subjectId }) =>
              `perform ${own.fn("approve_leave_request")}(${subjectId}::uuid);`,
          },
        ],
};

const REQUIRES = ["memberships", "permissions", "approvals", "ledger"] as const;

export const LEAVE: BlockSqlDefinition = {
  contributes: CONTRIBUTES,
  internal: ["leave_available", "leave_post", "leave_posted"],
  name: "leave",
  scopes: ["tenant"],
  title: "Leave",
  description:
    'Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover. With employees, requests carry the employee_id of their member, or belong to an employee with owner "employee". Balances can live in the app\'s own table of signed amounts instead of the ledger.',
  requires: [...REQUIRES],
  dependencies: (layout) =>
    REQUIRES.filter(
      (name) =>
        !(
          name === "approvals" &&
          layout.modules?.["leave"]?.options?.["approvals"] === false
        ) &&
        !(
          name === "ledger" &&
          typeof layout.modules?.["leave"]?.tables?.["balances"] === "string"
        ),
    ),
  integrates: ["outbox", "audit", "employees", "share-links"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "Leave balances move onto the ledger block: each member gets an account per type and year, every leave_ledger row becomes a ledger transaction, and leave_ledger is dropped.",
      sql: (ctx) => (leaveBalancesTable(ctx) ? "" : leaveLedgerUpgrade(ctx)),
    },
    {
      from: 2,
      description:
        "With employees, leave requests gain employee_id, backfilled and kept current by triggers.",
      sql: (ctx) =>
        ctx.installed("employees") && !leaveByEmployee(ctx)
          ? employeeKeyBackfillSql(ctx.of("employees"), {
              owner: ctx,
              table: "requests",
            })
          : "",
    },
  ],
  names: LEAVE_NAMES,
  contract,
  build,
};
