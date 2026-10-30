import type { BlockSqlContext } from "../context.ts";
import type { LeaveLedgerParts } from "./leave-ledger.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { leaveTypeKey } from "./leave-feed.ts";
import {
  leaveConfidentialFilter,
  leaveConfidentialReader,
} from "./leave-owner.ts";
import { moduleOperations } from "./permissions-model.ts";

export function unpostTaken(ctx: BlockSqlContext, request: string): string {
  const b = (column: string): string => ctx.col("balances", column);

  return `delete from ${ctx.table("balances")} b where b.${b("request")} = ${request} and b.${b("kind")} = ${ctx.cast("balances", "kind", "'taken'")};`;
}

export function leaveBalanceFunctions(
  ctx: BlockSqlContext,
  parts: LeaveLedgerParts,
): string {
  const { owner } = parts;
  const employee = owner.employee;
  const balances = ctx.table("balances");
  const b = (column: string): string => ctx.col("balances", column);
  const has = (column: string): boolean => ctx.has("balances", column);
  const types = ctx.table("types");
  const ty = (column: string): string => ctx.col("types", column);
  const requests = ctx.table("requests");
  const q = (column: string): string => ctx.col("requests", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const members = ctx.of("memberships");
  const permissions = moduleOperations("leave");
  const request = ctx.permission("request", permissions.request);
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const ownerColumn = employee ? b("employee") : b("user");
  const key = employee ? "v_owner" : "v_user";

  if (employee ? !has("employee") : !has("user")) {
    throw new TypeError(
      `blocks.leave.columns.balances.${employee ? "employee" : "user"} keeps the owner of each balance row, so it can't be null`,
    );
  }

  const forbidden = (message: string): string =>
    fail("LEAVE_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("LEAVE_INVALID", message, "22023");

  const ownerDrop = (name: string, types: string): string =>
    employee ? `drop function if exists ${fn(name)}(${types});\n` : "";

  const effectiveCheck = (arg: string): string =>
    has("effectiveOn")
      ? ""
      : `
  if ${arg} is not null then
    ${fail("LEAVE_EFFECTIVE_UNSUPPORTED", "this leave balances table has no effective date column", "22023")}
  end if;`;

  const effective = (row: string): string =>
    has("effectiveOn") ? `${row}.${b("effectiveOn")}` : "null::date";

  const expires = (row: string): string =>
    has("expiresOn") ? `${row}.${b("expiresOn")}` : "null::date";

  const kindText = (row: string): string => `${row}.${b("kind")}::text`;

  const totals = (on: string): string => `select
      coalesce(sum(r.${b("amount")}) filter (where r.${b("amount")} > 0 and (${effective("r")} is null or ${effective("r")} <= ${on}) and (${expires("r")} is null or ${expires("r")} >= ${on})), 0) as live,
      coalesce(sum(r.${b("amount")}) filter (where r.${b("amount")} > 0 and ${expires("r")} < ${on}), 0) as expired,
      coalesce(-sum(r.${b("amount")}) filter (where r.${b("amount")} < 0), 0) as spent,
      coalesce(-sum(r.${b("amount")}) filter (where r.${b("amount")} < 0 and ${kindText("r")} = 'taken'), 0) as taken`;

  const balanceOf = (alias: string): string =>
    `(${alias}.live + least(${alias}.expired, ${alias}.spent) - ${alias}.spent)`;

  const asOf = (period: string): string =>
    `(case when ${period} = extract(year from current_date)::integer then current_date else make_date(${period}, 12, 31) end)`;

  const entryJson = (row: string): string =>
    `jsonb_build_object('id', ${row}.${b("id")}, 'organizationId', ${row}.${b("tenant")}, 'userId', ${has("user") ? `${row}.${b("user")}` : owner.userOf(`${row}.${ownerColumn}`)}${employee ? `, 'employeeId', ${row}.${b("employee")}` : ""}, 'typeId', ${row}.${b("type")}, 'kind', ${kindText(row)}, 'amount', ${row}.${b("amount")}::numeric(10, 2)::text, 'period', extract(year from coalesce(${effective(row)}, ${row}.${b("createdAt")}::date))::integer, 'expiresOn', ${expires(row)}, 'requestId', ${row}.${b("request")}, 'note', ${has("note") ? `${row}.${b("note")}` : "null"}, 'createdAt', ${row}.${b("createdAt")})`;

  const ownerInsert = `${employee && has("user") ? `${b("user")}, ` : ""}${ownerColumn}`;

  const ownerValue = (value: string): string =>
    `${employee && has("user") ? `${owner.userOf(value)}, ` : ""}${value}`;

  const adjusted = ctx.record({
    type: "leave_balance.adjusted",
    payload: `jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', ${employee ? "v_user, 'employeeId', v_owner" : "v_user"}, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period)`,
    subject: `'leave-ledger-entries/' || v_entry::text`,
    tenant: "adjust_leave_balance.tenant",
    audit: {
      category: "data",
      targetType: "leave_balance",
      recordId: "v_entry::text",
      summary: `'adjusted a leave balance by ' || adjust_leave_balance.amount::numeric(8, 2)::text`,
    },
  });

  const resolveOwner = (fnName: string): string =>
    employee
      ? `\n  ${owner.resolve(`${fnName}.tenant`, `${fnName}.user_id`, `${fnName}.employee_id`)}`
      : "";

  const readerCheck = (fnName: string): string =>
    `if not (${SERVICE_CALLER} or ${ctx.can("tenant", `${fnName}.tenant`, read)}
    or (coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", `${fnName}.tenant`, request)})${employee ? ` or ${owner.manages(`${fnName}.tenant`, "v_owner")}` : ""}) then
    ${forbidden("not allowed to read this member's leave balance")}
  end if;`;

  const sees = (fnName: string): string =>
    `(${leaveConfidentialReader(ctx, `${fnName}.tenant`)} or coalesce(v_user = auth.uid(), false)${employee ? ` or ${owner.manages(`${fnName}.tenant`, "v_owner")}` : ""})`;

  const ownerDeclare = employee
    ? "  v_owner uuid;\n  v_user uuid;"
    : (fnName: string): string =>
        `  v_user uuid := coalesce(${fnName}.user_id, auth.uid());`;

  const declareFor = (fnName: string): string =>
    typeof ownerDeclare === "string" ? ownerDeclare : ownerDeclare(fnName);

  const accrueOwners = employee
    ? `    select e.${owner.staff?.col("employees", "id") ?? ""} from ${owner.staff?.table("employees") ?? ""} e
    where e.${owner.staff?.col("employees", "tenant") ?? ""} = accrue_leave.tenant
      and (accrue_leave.user_ids is null or e.${owner.staff?.col("employees", "user") ?? ""} = any (accrue_leave.user_ids))
      and (accrue_leave.employee_ids is null or e.${owner.staff?.col("employees", "id") ?? ""} = any (accrue_leave.employee_ids))`
    : `    select m.${members.col("memberships", "user")} from ${members.table("memberships")} m
    where m.${members.col("memberships", "tenant")} = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m.${members.col("memberships", "user")} = any (accrue_leave.user_ids))`;

  return `
create or replace function ${fn("leave_post")}(tenant ${idType}, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null, expires_on date default null, effective_on date default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_id uuid;
begin
  ${
    has("note")
      ? ""
      : `if nullif(trim(leave_post.note), '') is not null then
    ${fail("LEAVE_NOTE_UNSUPPORTED", "this leave balances table has no note column", "22023")}
  end if;
  `
  }${
    has("expiresOn")
      ? ""
      : `if leave_post.expires_on is not null then
    ${fail("LEAVE_EXPIRY_UNSUPPORTED", "this leave balances table has no expiry column", "22023")}
  end if;
  `
  }${
    has("key")
      ? ""
      : `if leave_post.key is not null then
    ${fail("LEAVE_KEY_UNSUPPORTED", "this leave balances table has no key column, so it can't take an idempotency key", "22023")}
  end if;
  `
  }insert into ${balances} (${b("tenant")}, ${ownerInsert}, ${b("type")}, ${b("kind")}, ${b("amount")}, ${b("request")}${has("effectiveOn") ? `, ${b("effectiveOn")}` : ""}${has("expiresOn") ? `, ${b("expiresOn")}` : ""}${has("note") ? `, ${b("note")}` : ""}${has("key") ? `, ${b("key")}` : ""}${has("createdBy") ? `, ${b("createdBy")}` : ""})
  values (leave_post.tenant, ${ownerValue("leave_post.user_id")}, leave_post.type_id, ${ctx.cast("balances", "kind", "leave_post.kind")}, leave_post.amount, leave_post.request_id${has("effectiveOn") ? `, coalesce(leave_post.effective_on, (select r.${q("startsOn")} from ${requests} r where r.${q("id")} = leave_post.request_id), make_date(leave_post.period, 1, 1))` : ""}${has("expiresOn") ? ", leave_post.expires_on" : ""}${has("note") ? ", nullif(trim(leave_post.note), '')" : ""}${has("key") ? ", leave_post.key" : ""}${has("createdBy") ? ", auth.uid()" : ""})
  returning ${b("id")} into v_id;
  return v_id;
end;
$$;
revoke execute on function ${fn("leave_post")}(${idType}, uuid, uuid, text, numeric, integer, uuid, text, text, integer, date, date) from public, anon, authenticated;

create or replace function ${fn("leave_posted")}(tenant ${idType}, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select ${has("key") ? `exists (select 1 from ${balances} r where r.${b("tenant")} = leave_posted.tenant and r.${ownerColumn} = leave_posted.user_id and r.${b("type")} = leave_posted.type_id and r.${b("key")} = leave_posted.key)` : "false"}
$$;
revoke execute on function ${fn("leave_posted")}(${idType}, uuid, uuid, text) from public, anon, authenticated;

create or replace function ${fn("leave_available")}(tenant ${idType}, user_id uuid, type_id uuid, on_date date)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select ${balanceOf("z")} - ${parts.pending("leave_available.tenant", "leave_available.user_id", "leave_available.type_id", "extract(year from leave_available.on_date)::integer")}
  from (
    ${totals("leave_available.on_date")}
    from ${balances} r
    where r.${b("tenant")} = leave_available.tenant and r.${ownerColumn} = leave_available.user_id and r.${b("type")} = leave_available.type_id
  ) z
$$;
revoke execute on function ${fn("leave_available")}(${idType}, uuid, uuid, date) from public, anon, authenticated;

${ownerDrop("leave_balances", `${idType}, uuid, integer`)}create or replace function ${fn("leave_balances")}(tenant ${idType}, user_id uuid default null, period integer default null${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${declareFor("leave_balances")}
  v_period integer := coalesce(leave_balances.period, extract(year from current_date)::integer);
  v_on date;
  v_rows jsonb;
begin${resolveOwner("leave_balances")}
  ${readerCheck("leave_balances")}
  if ${key} is null then
    ${invalid(employee ? "name user_id or employee_id" : "name user_id")}
  end if;
  v_on := ${asOf("v_period")};
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t.${ty("id")}, 'key', ${leaveTypeKey(ctx, "t")}, 'name', t.${ty("name")}, 'unit', t.${ty("unit")},
      'userId', v_user${employee ? ", 'employeeId', v_owner" : ""}, 'period', v_period,
      'granted', (${balanceOf("z")} + z.taken)::numeric(10, 2)::text,
      'taken', z.taken::numeric(10, 2)::text,
      'pending', w.pending::numeric(10, 2)::text,
      'available', (${balanceOf("z")} - w.pending)::numeric(10, 2)::text
    ) order by t.${ty("name")}), '[]'::jsonb) into v_rows
  from ${types} t
  cross join lateral (
    ${totals("v_on")}
    from ${balances} r
    where r.${b("tenant")} = leave_balances.tenant and r.${ownerColumn} = ${key} and r.${b("type")} = t.${ty("id")}
  ) z
  cross join lateral (
    select ${parts.pending("leave_balances.tenant", key, `t.${ty("id")}`, "v_period")} as pending
  ) w
  where t.${ty("tenant")} = leave_balances.tenant and t.${ty("tracked")} and t.${ty("archivedAt")} is null${leaveConfidentialFilter(ctx, `t.${ty("id")}`, sees("leave_balances"))};
  return v_rows;
end;
$$;
${userGrant(`${fn("leave_balances")}(${idType}, uuid, integer${employee ? ", uuid" : ""})`)}

${ownerDrop("leave_ledger_entries", `${idType}, uuid, integer, uuid`)}create or replace function ${fn("leave_ledger_entries")}(tenant ${idType}, user_id uuid default null, period integer default null, type_id uuid default null${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${declareFor("leave_ledger_entries")}
  v_rows jsonb;
begin${resolveOwner("leave_ledger_entries")}
  ${readerCheck("leave_ledger_entries")}
  select coalesce(jsonb_agg(${entryJson("y")} order by y.${b("createdAt")} desc, y.${b("id")} desc), '[]'::jsonb) into v_rows
  from ${balances} y
  where y.${b("tenant")} = leave_ledger_entries.tenant and y.${ownerColumn} = ${key}
    and (leave_ledger_entries.period is null or extract(year from coalesce(${effective("y")}, y.${b("createdAt")}::date))::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or y.${b("type")} = leave_ledger_entries.type_id)${leaveConfidentialFilter(ctx, `y.${b("type")}`, sees("leave_ledger_entries"))};
  return v_rows;
end;
$$;
${userGrant(`${fn("leave_ledger_entries")}(${idType}, uuid, integer, uuid${employee ? ", uuid" : ""})`)}

drop function if exists ${fn("adjust_leave_balance")}(${idType}, uuid, uuid, numeric, integer, text, text);
${employee ? `drop function if exists ${fn("adjust_leave_balance")}(${idType}, uuid, uuid, numeric, integer, text, text, uuid);\n` : ""}drop function if exists ${fn("adjust_leave_balance")}(${idType}, uuid, uuid, numeric, integer, text, text${employee ? ", uuid" : ""}, date);
create or replace function ${fn("adjust_leave_balance")}(tenant ${idType}, user_id uuid, type_id uuid, amount numeric, period integer default null, kind text default 'adjustment', note text default null${employee ? ", employee_id uuid default null" : ""}, expires_on date default null, effective_on date default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from coalesce(adjust_leave_balance.effective_on, current_date))::integer);
  v_entry uuid;
  v_row jsonb;${employee ? "\n  v_owner uuid;\n  v_user uuid;" : "\n  v_user uuid := adjust_leave_balance.user_id;"}
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "adjust_leave_balance.tenant", manage)}) then
    ${forbidden("not allowed to adjust leave balances")}
  end if;
  if coalesce(adjust_leave_balance.kind, 'adjustment') not in ('grant', 'adjustment') then
    ${invalid("kind must be grant or adjustment")}
  end if;
  if adjust_leave_balance.amount is null or adjust_leave_balance.amount = 0 then
    ${invalid("amount must not be zero")}
  end if;${effectiveCheck("adjust_leave_balance.effective_on")}
${
  employee
    ? `  if adjust_leave_balance.user_id is null and adjust_leave_balance.employee_id is null then
    ${invalid("name user_id or employee_id")}
  end if;
  ${owner.resolve("adjust_leave_balance.tenant", "adjust_leave_balance.user_id", "adjust_leave_balance.employee_id")}
  if v_owner is null then
    ${invalid("no employee record for that member in this organization")}
  end if;`
    : `  if not ${owner.exists("adjust_leave_balance.tenant", "adjust_leave_balance.user_id")} then
    ${invalid("the user is not a member of this organization")}
  end if;`
}
  if not exists (select 1 from ${types} t where t.${ty("id")} = adjust_leave_balance.type_id and t.${ty("tenant")} = adjust_leave_balance.tenant) then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  v_entry := ${fn("leave_post")}(adjust_leave_balance.tenant, ${key}, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note, null, null, adjust_leave_balance.expires_on, adjust_leave_balance.effective_on);
  select ${entryJson("y")} into v_row from ${balances} y where y.${b("id")} = v_entry;
  ${adjusted}
  return v_row;
end;
$$;
${userGrant(`${fn("adjust_leave_balance")}(${idType}, uuid, uuid, numeric, integer, text, text${employee ? ", uuid" : ""}, date, date)`)}

${ownerDrop("accrue_leave", `${idType}, uuid, numeric, integer, uuid[], text, text`)}drop function if exists ${fn("accrue_leave")}(${idType}, uuid, numeric, integer, uuid[], text, text${employee ? ", uuid[]" : ""});
create or replace function ${fn("accrue_leave")}(tenant ${idType}, type_id uuid, amount numeric default null, period integer default null, user_ids uuid[] default null, idempotency_key text default null, note text default null${employee ? ", employee_ids uuid[] default null" : ""}, effective_on date default null)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type ${types}%rowtype;
  v_amount numeric;
  v_owner uuid;
  v_count integer := 0;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "accrue_leave.tenant", manage)}) then
    ${forbidden("not allowed to accrue leave")}
  end if;
  select * into v_type from ${types} t where t.${ty("id")} = accrue_leave.type_id and t.${ty("tenant")} = accrue_leave.tenant;
  if not found then
    ${fail("LEAVE_TYPE_NOT_FOUND", "leave type not found", "P0002")}
  end if;
  v_amount := ${ctx.has("types", "allowance") ? `coalesce(accrue_leave.amount, v_type.${ty("allowance")})` : "accrue_leave.amount"};
  if v_amount is null or v_amount <= 0 then
    ${invalid("name an amount, or give the type an allowance")}
  end if;${effectiveCheck("accrue_leave.effective_on")}
  for v_owner in
${accrueOwners}
  loop
    continue when accrue_leave.idempotency_key is not null
      and ${fn("leave_posted")}(accrue_leave.tenant, v_owner, v_type.${ty("id")}, accrue_leave.idempotency_key);
    perform ${fn("leave_post")}(accrue_leave.tenant, v_owner, v_type.${ty("id")}, 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from coalesce(accrue_leave.effective_on, current_date))::integer), null, accrue_leave.note, accrue_leave.idempotency_key,
      null, null, accrue_leave.effective_on);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("accrue_leave")}(${idType}, uuid, numeric, integer, uuid[], text, text${employee ? ", uuid[]" : ""}, date)`)}

create or replace function ${fn("close_leave_year")}(tenant ${idType}, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_on date := make_date(close_leave_year.period, 12, 31);
  v_row record;
  v_written integer := 0;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "close_leave_year.tenant", manage)}) then
    ${forbidden("not allowed to close leave periods")}
  end if;
  if close_leave_year.period is null then
    ${invalid("name the period to close")}
  end if;${
    has("effectiveOn")
      ? ""
      : `
  ${fail("LEAVE_EFFECTIVE_UNSUPPORTED", "this leave balances table has no effective date column, so a period can't close", "22023")}`
  }
  for v_row in
    select o.owner_id, t.${ty("id")} as type_id, ${balanceOf("z")} as balance${ctx.has("types", "carryoverMax") ? `, t.${ty("carryoverMax")} as carry_max` : ", null::numeric as carry_max"}
    from ${types} t
    cross join lateral (select distinct x.${ownerColumn} as owner_id from ${balances} x where x.${b("tenant")} = close_leave_year.tenant and x.${b("type")} = t.${ty("id")}) o
    cross join lateral (
      ${totals("v_on")}
      from ${balances} r
      where r.${b("tenant")} = close_leave_year.tenant and r.${ownerColumn} = o.owner_id and r.${b("type")} = t.${ty("id")}
    ) z
    where t.${ty("tenant")} = close_leave_year.tenant and t.${ty("tracked")}
  loop
    continue when v_row.balance <= coalesce(v_row.carry_max, v_row.balance)
      or exists (select 1 from ${balances} x where x.${b("tenant")} = close_leave_year.tenant and x.${ownerColumn} = v_row.owner_id
        and x.${b("type")} = v_row.type_id and ${kindText("x")} = 'expiry' and ${effective("x")} = v_on);
    perform ${fn("leave_post")}(close_leave_year.tenant, v_row.owner_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry_max), close_leave_year.period,
      null, null, null, null, null, v_on);
    v_written := v_written + 1;
  end loop;
  return v_written;
end;
$$;
${userGrant(`${fn("close_leave_year")}(${idType}, integer)`)}
`;
}
