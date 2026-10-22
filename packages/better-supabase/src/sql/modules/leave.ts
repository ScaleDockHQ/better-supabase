import type { LeaveEvents } from "../../blocks/leave/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  pageSize,
  schemaPreamble,
  SERVICE_CALLER,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS, moduleOperations } from "./access-model.ts";
import { policyOf, policySnapshot } from "./approvals-policies.ts";
import { LEAVE_REQUEST_SUBJECT } from "./approvals.ts";
import { leaveLedgerFunctions, leaveLedgerUpgrade } from "./leave-ledger.ts";

const WHERE = "blocks.leave.options";

const REQUEST_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "typeId",
  "startsOn",
  "endsOn",
  "amount",
  "approvalId",
] as const;

const ADJUSTED_PAYLOAD = [
  "organizationId",
  "id",
  "userId",
  "typeId",
  "kind",
  "amount",
  "period",
] as const;

const EVENTS: BlockSqlEvents<LeaveEvents> = {
  "leave.requested": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.approved": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.cancelled": { subject: "leave-requests", payload: REQUEST_PAYLOAD },
  "leave.adjusted": {
    subject: "leave-ledger-entries",
    payload: ADJUSTED_PAYLOAD,
  },
};

const NAMES: BlockSqlNames = {
  events: EVENTS,
  hooks: ["before_leave_request", "after_leave_request"],
  options: ["policy", "workingDays", "allowNegative", "extraColumns"],
  tables: {
    types: {
      name: "leave_types",
      lifecycle: { tenant: "tenant", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        key: "key",
        name: "name",
        unit: "unit",
        paid: "paid",
        tracked: "tracked",
        allowance: "allowance",
        carryoverMax: "carryover_max",
        color: "color",
        archivedAt: "archived_at",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    requests: {
      name: "leave_requests",
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        user: "user_id",
        type: "type_id",
        startsOn: "starts_on",
        endsOn: "ends_on",
        partial: "partial",
        amount: "amount",
        note: "note",
        approval: "approval_id",
        approvedAt: "approved_at",
        cancelledAt: "cancelled_at",
        cancelledBy: "cancelled_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
  },
};

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

function build(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const approvals = ctx.of("approvals");

  if (approvals.mode === "custom") {
    throw new TypeError(
      "blocks.leave needs the approvals tables; approvals can't be in custom mode",
    );
  }

  const types = ctx.table("types");
  const requests = ctx.table("requests");
  const ty = (column: string): string => ctx.col("types", column);
  const q = (column: string): string => ctx.col("requests", column);
  const ar = approvals.table("requests");
  const a = (column: string): string => approvals.col("requests", column);
  const fn = (name: string): string => ctx.fn(name);
  const permissions = moduleOperations("leave");
  const request = ctx.permission("request", permissions.request);
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const policy = leavePolicy(ctx);
  const working = `array[${workingDaysOf(ctx).join(", ")}]`;
  const allowNegative = ctx.flag("allowNegative", false);
  const idType = ctx.idType;
  const members = ctx.of("tenant");
  const extras = ctx.extraColumns("requests", RESERVED);
  const extra = extraFieldsArg(extras);

  const isMember = (tenant: string, user: string): string =>
    `exists (select 1 from ${members.table("memberships")} m where m.${members.col("memberships", "tenant")} = ${tenant} and m.${members.col("memberships", "user")} = ${user})`;

  const forbidden = (message: string): string =>
    fail("LEAVE_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("LEAVE_INVALID", message, "22023");

  const status = (row: string, approval: string): string =>
    `case when ${row}.${q("cancelledAt")} is not null then 'cancelled' when ${row}.${q("approvedAt")} is not null then 'approved' when ${approval}.${a("status")} in ('rejected', 'expired') then 'rejected' when ${approval}.${a("status")} = 'cancelled' then 'cancelled' else 'pending' end`;

  const typeJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${ty("id")}, 'organizationId', ${row}.${ty("tenant")}, 'key', ${row}.${ty("key")}, 'name', ${row}.${ty("name")}, 'unit', ${row}.${ty("unit")}, 'paid', ${row}.${ty("paid")}, 'tracked', ${row}.${ty("tracked")}, 'allowance', ${row}.${ty("allowance")}::text, 'carryoverMax', ${row}.${ty("carryoverMax")}::text, 'color', ${row}.${ty("color")}, 'archivedAt', ${row}.${ty("archivedAt")}, 'createdAt', ${row}.${ty("createdAt")}, 'updatedAt', ${row}.${ty("updatedAt")})`;

  const requestJson = (row: string, approval: string): string =>
    `jsonb_build_object('id', ${row}.${q("id")}, 'organizationId', ${row}.${q("tenant")}, 'userId', ${row}.${q("user")}, 'typeId', ${row}.${q("type")}, 'startsOn', ${row}.${q("startsOn")}, 'endsOn', ${row}.${q("endsOn")}, 'partial', ${row}.${q("partial")}, 'amount', ${row}.${q("amount")}::text, 'note', ${row}.${q("note")}, 'status', ${status(row, approval)}, 'approvalId', ${row}.${q("approval")}, 'approvedAt', ${row}.${q("approvedAt")}, 'cancelledAt', ${row}.${q("cancelledAt")}, 'createdAt', ${row}.${q("createdAt")}, 'updatedAt', ${row}.${q("updatedAt")}${extraFieldsJson(row, extras)})`;

  const requestRecord = (type: string, row: string, summary: string): string =>
    ctx.record({
      type,
      payload: `jsonb_build_object('organizationId', ${row}.${q("tenant")}, 'id', ${row}.${q("id")}, 'userId', ${row}.${q("user")}, 'typeId', ${row}.${q("type")}, 'startsOn', ${row}.${q("startsOn")}, 'endsOn', ${row}.${q("endsOn")}, 'amount', ${row}.${q("amount")}::text, 'approvalId', ${row}.${q("approval")})`,
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
    `${alias}.${q("cancelledAt")} is null and ${alias}.${q("approvedAt")} is null and ${approval}.${a("status")} = 'pending'`;

  const balanceCheck = allowNegative
    ? ""
    : `
  if v_type.${ty("tracked")} and ${fn("leave_available")}(request_leave.tenant, v_me, v_type.${ty("id")}, extract(year from request_leave.starts_on)::integer) < v_amount then
    ${fail("LEAVE_BALANCE_EXCEEDED", "this request is more than the available balance", "23514")}
  end if;`;

  const tables = ctx.manages
    ? `create table if not exists ${types} (
  ${ty("id")} uuid primary key default gen_random_uuid(),
  ${ty("tenant")} ${idType} not null,
  ${ty("key")} text not null check (${ty("key")} ~ '^[a-z][a-z0-9_-]{0,62}$'),
  ${ty("name")} text not null check (length(${ty("name")}) between 1 and 100),
  ${ty("unit")} text not null default 'days' check (${ty("unit")} in ('days', 'hours')),
  ${ty("paid")} boolean not null default true,
  -- Untracked types (unpaid leave, say) book no ledger entries and skip the balance check.
  ${ty("tracked")} boolean not null default true,
  -- What accrue_leave grants each member per period when it names no amount.
  ${ty("allowance")} numeric(8, 2) check (${ty("allowance")} is null or ${ty("allowance")} >= 0),
  -- How much close_leave_year carries into the next period; null carries everything.
  ${ty("carryoverMax")} numeric(8, 2) check (${ty("carryoverMax")} is null or ${ty("carryoverMax")} >= 0),
  ${ty("color")} text check (${ty("color")} is null or ${ty("color")} ~ '^#[0-9a-fA-F]{6}$'),
  ${ty("archivedAt")} timestamptz,
  ${ty("createdAt")} timestamptz not null default now(),
  ${ty("updatedAt")} timestamptz not null default now(),
  unique (${ty("tenant")}, ${ty("key")}),
  unique (${ty("tenant")}, ${ty("id")})
);
${lockTable(types, { read: true })}
drop policy if exists "leave_types_read" on ${types};
create policy "leave_types_read" on ${types} for select to authenticated
  using (${ctx.scope.check(ty("tenant"), request)} or ${ctx.scope.check(ty("tenant"), read)});

create table if not exists ${requests} (
  ${q("id")} uuid primary key default gen_random_uuid(),
  ${q("tenant")} ${idType} not null,
  ${q("user")} uuid not null,
  ${q("type")} uuid not null,
  ${q("startsOn")} date not null,
  ${q("endsOn")} date not null,
  ${q("partial")} text not null default 'full' check (${q("partial")} in ('full', 'morning', 'afternoon', 'hours')),
  -- Working days, or hours for an hours type, that the request books.
  ${q("amount")} numeric(8, 2) not null check (${q("amount")} > 0),
  ${q("note")} text check (${q("note")} is null or length(${q("note")}) <= 2000),
  ${q("approval")} uuid references ${ar} (${a("id")}) on delete set null,
  ${q("approvedAt")} timestamptz,
  ${q("cancelledAt")} timestamptz,
  ${q("cancelledBy")} uuid,
  ${q("createdAt")} timestamptz not null default now(),
  ${q("updatedAt")} timestamptz not null default now(),
  check (${q("endsOn")} >= ${q("startsOn")}),
  foreign key (${q("tenant")}, ${q("type")}) references ${types} (${ty("tenant")}, ${ty("id")}) on delete restrict
);${addExtraColumns(requests, extras)}
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_user_idx`)} on ${requests} (${q("tenant")}, ${q("user")}, ${q("startsOn")} desc);
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_dates_idx`)} on ${requests} (${q("tenant")}, ${q("startsOn")}, ${q("endsOn")});
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_approval_idx`)} on ${requests} (${q("approval")}) where ${q("approval")} is not null;
create index if not exists ${sqlIdent(`${ctx.tableName("requests").name}_type_idx`)} on ${requests} (${q("tenant")}, ${q("type")});
${lockTable(requests, { read: true })}
drop policy if exists "leave_requests_read" on ${requests};
create policy "leave_requests_read" on ${requests} for select to authenticated
  using (${q("user")} = (select auth.uid()) or ${ctx.scope.check(q("tenant"), read)});

`
    : "";

  const pending = (
    tenant: string,
    user: string,
    type: string,
    year: string,
  ): string =>
    `coalesce((select sum(r.${q("amount")}) from ${requests} r
      left join ${ar} p on p.${a("id")} = r.${q("approval")}
      where r.${q("tenant")} = ${tenant} and r.${q("user")} = ${user}
        and r.${q("type")} = ${type} and ${period("r")} = ${year}
        and ${pendingIn("r", "p")}), 0)`;

  return `${schemaPreamble(ctx)}
${tables}${leaveLedgerFunctions(ctx, { isMember, pending })}
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

-- Creates or updates a leave type by key.
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
  end if;
  insert into ${types} (${ty("tenant")}, ${ty("key")}, ${ty("name")}, ${ty("unit")}, ${ty("paid")}, ${ty("tracked")}, ${ty("allowance")}, ${ty("carryoverMax")}, ${ty("color")})
  values (save_leave_type.tenant, save_leave_type.key, save_leave_type.name, coalesce(save_leave_type.unit, 'days'), coalesce(save_leave_type.paid, true), coalesce(save_leave_type.tracked, true), save_leave_type.allowance, save_leave_type.carryover_max, save_leave_type.color)
  on conflict (${ty("tenant")}, ${ty("key")}) do update
    set ${ty("name")} = excluded.${ty("name")}, ${ty("unit")} = excluded.${ty("unit")}, ${ty("paid")} = excluded.${ty("paid")},
      ${ty("tracked")} = excluded.${ty("tracked")}, ${ty("allowance")} = excluded.${ty("allowance")},
      ${ty("carryoverMax")} = excluded.${ty("carryoverMax")}, ${ty("color")} = excluded.${ty("color")},
      ${ty("archivedAt")} = null, ${ty("updatedAt")} = now()
  returning * into v_row;
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
${extra.drop(fn("request_leave"), `${idType}, uuid, date, date, text, numeric, text`)}
create or replace function ${fn("request_leave")}(tenant ${idType}, type_id uuid, starts_on date, ends_on date, partial text default 'full', hours numeric default null, note text default null${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_me uuid := auth.uid();
  v_type ${types}%rowtype;
  v_partial text := coalesce(request_leave.partial, 'full');
  v_amount numeric;
  v_row ${requests}%rowtype;
  v_approval ${ar}%rowtype;
  v_request jsonb;
begin
  if v_me is null or not ${ctx.can("tenant", "request_leave.tenant", request)} then
    ${forbidden("not allowed to request leave here")}
  end if;
  select * into v_type from ${types} x
    where x.${ty("id")} = request_leave.type_id and x.${ty("tenant")} = request_leave.tenant and x.${ty("archivedAt")} is null;
  if not found then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  if request_leave.starts_on is null or request_leave.ends_on is null or request_leave.ends_on < request_leave.starts_on then
    ${invalid("ends_on must be on or after starts_on")}
  end if;
  if v_partial not in ('full', 'morning', 'afternoon', 'hours') then
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
    end if;
    v_amount := ${fn("leave_working_days")}(request_leave.starts_on, request_leave.ends_on)
      * case when v_partial = 'full' then 1 else 0.5 end;
  end if;
  if v_amount <= 0 then
    ${invalid("the request covers no working days")}
  end if;
  perform pg_advisory_xact_lock(hashtextextended('leave:' || request_leave.tenant::text || ':' || v_me::text, 0));
  if exists (
    select 1 from ${requests} r
    left join ${ar} p on p.${a("id")} = r.${q("approval")}
    where r.${q("tenant")} = request_leave.tenant and r.${q("user")} = v_me
      and r.${q("cancelledAt")} is null and (r.${q("approvedAt")} is not null or p.${a("status")} = 'pending')
      and daterange(r.${q("startsOn")}, r.${q("endsOn")}, '[]') && daterange(request_leave.starts_on, request_leave.ends_on, '[]')
      and not (r.${q("partial")} = 'morning' and v_partial = 'afternoon')
      and not (r.${q("partial")} = 'afternoon' and v_partial = 'morning')
  ) then
    ${fail("LEAVE_OVERLAP", "this overlaps another leave request", "23P01")}
  end if;${balanceCheck}
  ${ctx.hook("before_leave_request", [
    [idType, "request_leave.tenant"],
    ["uuid", `v_type.${ty("id")}`],
    ["date", "request_leave.starts_on"],
    ["date", "request_leave.ends_on"],
    ["numeric", "v_amount"],
  ])}
  insert into ${requests} (${q("tenant")}, ${q("user")}, ${q("type")}, ${q("startsOn")}, ${q("endsOn")}, ${q("partial")}, ${q("amount")}, ${q("note")})
  values (request_leave.tenant, v_me, v_type.${ty("id")}, request_leave.starts_on, request_leave.ends_on, v_partial, v_amount, nullif(trim(request_leave.note), ''))
  returning * into v_row;${writeExtraColumns(requests, extras, "request_leave.fields", `x.${q("id")} = v_row.${q("id")}`, "v_row")}
  v_request := ${approvals.fn("open_approval")}(
    request_leave.tenant, ${sqlString(LEAVE_REQUEST_SUBJECT)}, v_row.${q("id")}::text, 'approve',
    ${sqlString(policy)}::jsonb, v_row.${q("note")},
    jsonb_build_object('userId', v_me, 'typeId', v_type.${ty("id")}, 'type', v_type.${ty("name")}, 'startsOn', v_row.${q("startsOn")}, 'endsOn', v_row.${q("endsOn")}, 'amount', v_amount::text, 'unit', v_type.${ty("unit")})
  );
  update ${requests} x set ${q("approval")} = (v_request ->> 'id')::uuid
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
  select * into v_approval from ${ar} x where x.${a("id")} = v_row.${q("approval")};
  ${requestRecord("leave.requested", "v_row", "requested leave")}
  ${ctx.hook("after_leave_request", [["uuid", `v_row.${q("id")}`]])}
  return ${requestJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("request_leave")}(${idType}, uuid, date, date, text, numeric, text${extra.type})`)}

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
  perform ${fn("leave_post")}(v_row.${q("tenant")}, v_row.${q("user")}, v_row.${q("type")}, 'taken', -v_row.${q("amount")}, ${period("v_row")}, v_row.${q("id")})
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
  v_row ${requests}%rowtype;
  v_approval ${ar}%rowtype;
  v_manager boolean;
begin
  select * into v_row from ${requests} x where x.${q("id")} = cancel_leave_request.request_id for update;
  if not found then
    ${fail("LEAVE_REQUEST_NOT_FOUND", "leave request not found", "P0002")}
  end if;
  v_manager := ${SERVICE_CALLER} or ${ctx.can("tenant", `v_row.${q("tenant")}`, manage)};
  if not (v_manager or v_row.${q("user")} = auth.uid()) then
    ${forbidden("not allowed to cancel this leave request")}
  end if;
  if v_row.${q("cancelledAt")} is not null then
    ${fail("LEAVE_REQUEST_CLOSED", "this leave request is already cancelled", "55000")}
  end if;
  if not v_manager and v_row.${q("approvedAt")} is not null and v_row.${q("startsOn")} <= current_date then
    ${forbidden("leave that has started can only be cancelled by a manager")}
  end if;
  update ${ar} p set ${a("status")} = 'cancelled', ${a("decidedAt")} = now()
    where p.${a("id")} = v_row.${q("approval")} and p.${a("status")} = 'pending';
  if v_row.${q("approvedAt")} is not null then
    perform ${fn("leave_post")}(v_row.${q("tenant")}, v_row.${q("user")}, v_row.${q("type")}, 'taken', v_row.${q("amount")}, ${period("v_row")}, v_row.${q("id")}, 'cancelled')
    from ${types} t where t.${ty("id")} = v_row.${q("type")} and t.${ty("tracked")};
  end if;
  update ${requests} x set ${q("cancelledAt")} = now(), ${q("cancelledBy")} = auth.uid(), ${q("updatedAt")} = now()
    where x.${q("id")} = v_row.${q("id")}
    returning * into v_row;
  select * into v_approval from ${ar} x where x.${a("id")} = v_row.${q("approval")};
  ${requestRecord("leave.cancelled", "v_row", "cancelled leave")}
  return ${requestJson("v_row", "v_approval")};
end;
$$;
${userGrant(`${fn("cancel_leave_request")}(uuid)`)}

-- Requests that overlap a date range, earliest first: the caller's, or
-- everyone's with the read permission.
create or replace function ${fn("list_leave_requests")}(tenant ${idType}, user_id uuid default null, status text default null, starts date default null, ends date default null, everyone boolean default false, page_size integer default 100)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_reader boolean := ${SERVICE_CALLER} or ${ctx.can("tenant", "list_leave_requests.tenant", read)};
  v_rows jsonb;
begin
  if not (v_reader or ${ctx.can("tenant", "list_leave_requests.tenant", request)}) then
    ${forbidden("not allowed to list leave requests")}
  end if;
  if not v_reader and (coalesce(list_leave_requests.everyone, false) or (list_leave_requests.user_id is not null and list_leave_requests.user_id <> auth.uid())) then
    ${forbidden("not allowed to read another member's leave")}
  end if;
  select coalesce(jsonb_agg(z.item order by z.starts, z.created), '[]'::jsonb) into v_rows
  from (
    select ${requestJson("r", "p")} as item, r.${q("startsOn")} as starts, r.${q("createdAt")} as created
    from ${requests} r
    left join ${ar} p on p.${a("id")} = r.${q("approval")}
    where r.${q("tenant")} = list_leave_requests.tenant
      and (case
        when coalesce(list_leave_requests.everyone, false) then true
        when list_leave_requests.user_id is not null then r.${q("user")} = list_leave_requests.user_id
        else r.${q("user")} = auth.uid()
      end)
      and (list_leave_requests.status is null or ${status("r", "p")} = list_leave_requests.status)
      and (list_leave_requests.starts is null or r.${q("endsOn")} >= list_leave_requests.starts)
      and (list_leave_requests.ends is null or r.${q("startsOn")} <= list_leave_requests.ends)
    order by r.${q("startsOn")}, r.${q("createdAt")}
    limit ${pageSize("list_leave_requests.page_size", 100, 500)}
  ) z;
  return v_rows;
end;
$$;
${userGrant(`${fn("list_leave_requests")}(${idType}, uuid, text, date, date, boolean, integer)`)}

`;
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const extra = extraFieldsArg(ctx.extraColumns("requests", RESERVED)).contract;

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
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "cancel_leave_request", args: ["uuid"], returns: "jsonb" },
    {
      name: "leave_balances",
      args: ["{id}", "uuid", "integer"],
      returns: "jsonb",
    },
    {
      name: "list_leave_requests",
      args: ["{id}", "uuid", "text", "date", "date", "boolean", "integer"],
      returns: "jsonb",
    },
  ];
}

export const LEAVE: BlockSqlDefinition = {
  internal: ["leave_available", "leave_post", "leave_posted"],
  name: "leave",
  scopes: ["tenant"],
  title: "Leave",
  description:
    "Leave types, requests that go through approvals, and a balance ledger per member and year with accruals, adjustments and a year-end carryover.",
  requires: ["tenant", "access", "approvals", "ledger"],
  integrates: ["outbox", "audit"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 2,
  upgrades: [
    {
      from: 1,
      description:
        "Leave balances move onto the ledger block: each member gets an account per type and year, every leave_ledger row becomes a ledger transaction, and leave_ledger is dropped.",
      sql: leaveLedgerUpgrade,
    },
  ],
  names: NAMES,
  contract,
  build,
};
