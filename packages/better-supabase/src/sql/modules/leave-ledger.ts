import type { BlockSqlContext } from "../context.ts";
import type { LeaveOwner } from "./leave-owner.ts";

import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { leaveTypeKey } from "./leave-feed.ts";
import { ledgerRebalance, ledgerTables } from "./ledger.ts";
import { moduleOperations } from "./permissions-model.ts";

/** What the balance functions need from the rest of the leave module. */
export interface LeaveLedgerParts {
  readonly owner: LeaveOwner;
  /** The amount a member's pending requests of one type and period book. */
  readonly pending: (
    tenant: string,
    user: string,
    type: string,
    period: string,
  ) => string;
}

/** Leave amounts are numeric(8, 2); ledger amounts are hundredths. */
const SCALE = 100;

/** The code of a member's account for one type and period. */
const userCode = (type: string, user: string, period: string): string =>
  `'leave:' || ${type}::text || ':' || ${user}::text || ':' || ${period}::text`;

/** A ledger amount in hundredths as the numeric(8, 2) text leave returns. */
const decimalText = (amount: string): string =>
  `(${amount}::numeric / ${SCALE})::numeric(10, 2)::text`;

/**
 * Leave balances on the ledger block: each member has an account per type and
 * period (amounts in hundredths of the type's unit), and every grant, accrual,
 * adjustment, taken day, carryover and expiry is a ledger transaction against
 * the type's pool or taken account, or another period's account.
 */
export function leaveLedgerFunctions(
  ctx: BlockSqlContext,
  parts: LeaveLedgerParts,
): string {
  const ledger = ctx.of("ledger");
  const accounts = ledger.table("accounts");
  const transactions = ledger.table("transactions");
  const entries = ledger.table("entries");
  const balances = ledger.table("balances");
  const la = (column: string): string => ledger.col("accounts", column);
  const lt = (column: string): string => ledger.col("transactions", column);
  const le = (column: string): string => ledger.col("entries", column);
  const lb = (column: string): string => ledger.col("balances", column);
  const types = ctx.table("types");
  const ty = (column: string): string => ctx.col("types", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;
  const members = ctx.of("memberships");
  const permissions = moduleOperations("leave");
  const request = ctx.permission("request", permissions.request);
  const read = ctx.permission("read", permissions.read);
  const manage = ctx.permission("manage", permissions.manage);
  const { owner } = parts;
  const employee = owner.employee;

  const ownerDrop = (name: string, types: string): string =>
    employee ? `drop function if exists ${fn(name)}(${types});\n` : "";

  const forbidden = (message: string): string =>
    fail("LEAVE_FORBIDDEN", message);

  const invalid = (message: string): string =>
    fail("LEAVE_INVALID", message, "22023");

  /** A member's account of one type and period, created on first use. */
  const accountFor = (
    tenant: string,
    user: string,
    type: string,
    unit: string,
    period: string,
  ): string =>
    `${ledger.fn("ledger_account_for")}(${tenant}, 'leave', ${userCode(type, user, period)}, 'Leave', ${unit}, 2::smallint,
    'leave-types', ${type}::text, ${owner.userOf(user)}, true, ${read}, 'leave',
    jsonb_build_object('userId', ${owner.userOf(user)}${employee ? `, 'employeeId', ${user}` : ""}, 'typeId', ${type}, 'period', ${period}))`;

  /** The entries on members' leave accounts, with their transactions. */
  const memberEntries = `${entries} y
    join ${accounts} x on x.${la("id")} = y.${le("account")} and x.${la("managedBy")} = 'leave' and x.${la("kind")} = 'leave'
    join ${transactions} r on r.${lt("id")} = y.${le("transaction")}`;

  const entryJson = `jsonb_build_object('id', y.${le("id")}, 'organizationId', x.${la("tenant")}, 'userId', x.${la("owner")}${employee ? `, 'employeeId', (x.${la("metadata")} ->> 'employeeId')::uuid` : ""},
      'typeId', (x.${la("metadata")} ->> 'typeId')::uuid, 'kind', substr(r.${lt("kind")}, 7), 'amount', ${decimalText(`y.${le("amount")}`)},
      'period', (x.${la("metadata")} ->> 'period')::integer,
      'requestId', case when r.${lt("referenceType")} = 'leave-requests' then r.${lt("referenceId")}::uuid end,
      'note', ${ledger.has("transactions", "memo") ? `r.${lt("memo")}` : "null"}, 'createdAt', y.${le("createdAt")})`;

  const adjusted = ctx.record({
    type: "leave.adjusted",
    payload: `jsonb_build_object('organizationId', adjust_leave_balance.tenant, 'id', v_entry, 'userId', ${employee ? "v_user, 'employeeId', v_owner" : "adjust_leave_balance.user_id"}, 'typeId', adjust_leave_balance.type_id, 'kind', coalesce(adjust_leave_balance.kind, 'adjustment'), 'amount', adjust_leave_balance.amount::numeric(8, 2)::text, 'period', v_period)`,
    subject: `'leave-ledger-entries/' || v_entry::text`,
    tenant: "adjust_leave_balance.tenant",
    audit: {
      category: "data",
      targetType: "leave_balance",
      recordId: "v_entry::text",
      summary: `'adjusted a leave balance by ' || adjust_leave_balance.amount::numeric(8, 2)::text`,
    },
  });

  const key = employee ? "v_owner" : "v_user";

  const y = (column: string): string =>
    owner.staff?.col("employees", column) ?? "";

  const accrueOwners = employee
    ? `    select e.${y("id")} from ${owner.staff?.table("employees") ?? ""} e
    where e.${y("tenant")} = accrue_leave.tenant
      and (accrue_leave.user_ids is null or e.${y("user")} = any (accrue_leave.user_ids))
      and (accrue_leave.employee_ids is null or e.${y("id")} = any (accrue_leave.employee_ids))`
    : `    select m.${members.col("memberships", "user")} from ${members.table("memberships")} m
    where m.${members.col("memberships", "tenant")} = accrue_leave.tenant
      and (accrue_leave.user_ids is null or m.${members.col("memberships", "user")} = any (accrue_leave.user_ids))`;

  return `
-- Posts one leave movement to a member's account of a type and period:
-- against the type's taken account for taken leave, the member's account
-- of to_period for a carryover, else the type's pool. Returns the ledger
-- transaction; with a key a second post returns the first.
create or replace function ${fn("leave_post")}(tenant ${idType}, user_id uuid, type_id uuid, kind text, amount numeric, period integer, request_id uuid default null, note text default null, key text default null, to_period integer default null)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_unit text;
  v_account uuid;
  v_counter uuid;
  v_amount bigint := round(leave_post.amount * ${SCALE});
begin
  select t.${ty("unit")} into v_unit from ${types} t where t.${ty("id")} = leave_post.type_id;
  v_account := ${accountFor("leave_post.tenant", "leave_post.user_id", "leave_post.type_id", "v_unit", "leave_post.period")};
  v_counter := case
    when leave_post.to_period is not null then
      ${accountFor("leave_post.tenant", "leave_post.user_id", "leave_post.type_id", "v_unit", "leave_post.to_period")}
    else ${ledger.fn("ledger_account_for")}(leave_post.tenant, 'leave_pool',
      'leave:' || leave_post.type_id::text || case when leave_post.kind = 'taken' then ':taken' else ':pool' end,
      case when leave_post.kind = 'taken' then 'Leave taken' else 'Leave pool' end, v_unit, 2::smallint,
      'leave-types', leave_post.type_id::text, null, true, ${read}, 'leave', null)
  end;
  return ${ledger.fn("ledger_post")}(leave_post.tenant, 'leave.' || leave_post.kind,
    jsonb_build_array(
      jsonb_build_object('account', v_account, 'amount', v_amount),
      jsonb_build_object('account', v_counter, 'amount', -v_amount)),
    case when leave_post.request_id is not null then 'leave-requests' end, leave_post.request_id::text,
    nullif(trim(leave_post.note), ''),
    case when leave_post.key is not null then 'leave:' || leave_post.user_id::text || ':' || leave_post.type_id::text || ':' || leave_post.key end,
    null,
    jsonb_build_object(${employee ? "'employeeId'" : "'userId'"}, leave_post.user_id, 'typeId', leave_post.type_id, 'period', leave_post.period, 'kind', leave_post.kind));
end;
$$;
revoke execute on function ${fn("leave_post")}(${idType}, uuid, uuid, text, numeric, integer, uuid, text, text, integer) from public, anon, authenticated;

-- Whether a member already has the leave movement with this key.
create or replace function ${fn("leave_posted")}(tenant ${idType}, user_id uuid, type_id uuid, key text)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select 1 from ${transactions} r where r.${lt("tenant")} = leave_posted.tenant
    and r.${lt("key")} = 'leave:' || leave_posted.user_id::text || ':' || leave_posted.type_id::text || ':' || leave_posted.key)
$$;
revoke execute on function ${fn("leave_posted")}(${idType}, uuid, uuid, text) from public, anon, authenticated;

-- A member's balance of one type for one period: the account's balance,
-- minus the requests still waiting for approval.
create or replace function ${fn("leave_available")}(tenant ${idType}, user_id uuid, type_id uuid, period integer)
returns numeric
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce((select b.${lb("balance")}::numeric / ${SCALE} from ${accounts} x join ${balances} b on b.${lb("account")} = x.${la("id")}
      where x.${la("tenant")} = leave_available.tenant and x.${la("code")} = ${userCode("leave_available.type_id", "leave_available.user_id", "leave_available.period")}), 0)
    - ${parts.pending("leave_available.tenant", "leave_available.user_id", "leave_available.type_id", "leave_available.period")}
$$;
revoke execute on function ${fn("leave_available")}(${idType}, uuid, uuid, integer) from public, anon, authenticated;

-- A member's balance of each tracked type for one period (default this
-- year): granted, taken, pending and available.
${ownerDrop("leave_balances", `${idType}, uuid, integer`)}create or replace function ${fn("leave_balances")}(tenant ${idType}, user_id uuid default null, period integer default null${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${
  employee
    ? `  v_owner uuid;
  v_user uuid;`
    : "  v_user uuid := coalesce(leave_balances.user_id, auth.uid());"
}
  v_period integer := coalesce(leave_balances.period, extract(year from current_date)::integer);
  v_rows jsonb;
begin${employee ? `\n  ${owner.resolve("leave_balances.tenant", "leave_balances.user_id", "leave_balances.employee_id")}` : ""}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "leave_balances.tenant", read)}
    or (coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", "leave_balances.tenant", request)})${employee ? ` or ${owner.manages("leave_balances.tenant", "v_owner")}` : ""}) then
    ${forbidden("not allowed to read this member's leave balance")}
  end if;
  if ${employee ? "v_owner" : "v_user"} is null then
    ${invalid(employee ? "name user_id or employee_id" : "name user_id")}
  end if;
  select coalesce(jsonb_agg(jsonb_build_object(
      'typeId', t.${ty("id")}, 'key', ${leaveTypeKey(ctx, "t")}, 'name', t.${ty("name")}, 'unit', t.${ty("unit")},
      'userId', v_user${employee ? ", 'employeeId', v_owner" : ""}, 'period', v_period,
      'granted', ${decimalText("coalesce(b.granted, 0)")},
      'taken', ${decimalText("coalesce(b.taken, 0)")},
      'pending', w.pending::numeric(10, 2)::text,
      'available', (coalesce(b.total, 0)::numeric / ${SCALE} - w.pending)::numeric(10, 2)::text
    ) order by t.${ty("name")}), '[]'::jsonb) into v_rows
  from ${types} t
  left join lateral (
    select sum(y.${le("amount")}) filter (where r.${lt("kind")} <> 'leave.taken') as granted,
      -sum(y.${le("amount")}) filter (where r.${lt("kind")} = 'leave.taken') as taken,
      sum(y.${le("amount")}) as total
    from ${memberEntries}
    where x.${la("tenant")} = leave_balances.tenant and x.${la("code")} = ${userCode(`t.${ty("id")}`, key, "v_period")}
  ) b on true
  cross join lateral (
    select ${parts.pending("leave_balances.tenant", key, `t.${ty("id")}`, "v_period")} as pending
  ) w
  where t.${ty("tenant")} = leave_balances.tenant and t.${ty("tracked")} and t.${ty("archivedAt")} is null;
  return v_rows;
end;
$$;
${userGrant(`${fn("leave_balances")}(${idType}, uuid, integer${employee ? ", uuid" : ""})`)}

-- A member's ledger entries of one period, newest first.
${ownerDrop("leave_ledger_entries", `${idType}, uuid, integer, uuid`)}create or replace function ${fn("leave_ledger_entries")}(tenant ${idType}, user_id uuid default null, period integer default null, type_id uuid default null${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
${
  employee
    ? `  v_owner uuid;
  v_user uuid;`
    : "  v_user uuid := coalesce(leave_ledger_entries.user_id, auth.uid());"
}
  v_rows jsonb;
begin${employee ? `\n  ${owner.resolve("leave_ledger_entries.tenant", "leave_ledger_entries.user_id", "leave_ledger_entries.employee_id")}` : ""}
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "leave_ledger_entries.tenant", read)}
    or (coalesce(v_user = auth.uid(), false) and ${ctx.can("tenant", "leave_ledger_entries.tenant", request)})${employee ? ` or ${owner.manages("leave_ledger_entries.tenant", "v_owner")}` : ""}) then
    ${forbidden("not allowed to read this member's leave balance")}
  end if;
  select coalesce(jsonb_agg(${entryJson} order by y.${le("createdAt")} desc, y.${le("id")} desc), '[]'::jsonb) into v_rows
  from ${memberEntries}
  where x.${la("tenant")} = leave_ledger_entries.tenant and ${employee ? `x.${la("metadata")} ->> 'employeeId' = v_owner::text` : `x.${la("owner")} = v_user`}
    and (leave_ledger_entries.period is null or (x.${la("metadata")} ->> 'period')::integer = leave_ledger_entries.period)
    and (leave_ledger_entries.type_id is null or x.${la("holderId")} = leave_ledger_entries.type_id::text);
  return v_rows;
end;
$$;
${userGrant(`${fn("leave_ledger_entries")}(${idType}, uuid, integer, uuid${employee ? ", uuid" : ""})`)}

-- Adds a grant or a manual adjustment (signed) to a member's balance.
${ownerDrop("adjust_leave_balance", `${idType}, uuid, uuid, numeric, integer, text, text`)}create or replace function ${fn("adjust_leave_balance")}(tenant ${idType}, user_id uuid, type_id uuid, amount numeric, period integer default null, kind text default 'adjustment', note text default null${employee ? ", employee_id uuid default null" : ""})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_period integer := coalesce(adjust_leave_balance.period, extract(year from current_date)::integer);
  v_transaction uuid;
  v_entry uuid;
  v_row jsonb;${owner.declare}
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "adjust_leave_balance.tenant", manage)}) then
    ${forbidden("not allowed to adjust leave balances")}
  end if;
  if coalesce(adjust_leave_balance.kind, 'adjustment') not in ('grant', 'adjustment') then
    ${invalid("kind must be grant or adjustment")}
  end if;
  if adjust_leave_balance.amount is null or adjust_leave_balance.amount = 0 then
    ${invalid("amount must not be zero")}
  end if;
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
  v_transaction := ${fn("leave_post")}(adjust_leave_balance.tenant, ${employee ? "v_owner" : "adjust_leave_balance.user_id"}, adjust_leave_balance.type_id,
    coalesce(adjust_leave_balance.kind, 'adjustment'), adjust_leave_balance.amount, v_period, null, adjust_leave_balance.note);
  select y.${le("id")}, ${entryJson} into v_entry, v_row
  from ${memberEntries}
  where y.${le("transaction")} = v_transaction and ${employee ? `x.${la("metadata")} ->> 'employeeId' = v_owner::text` : `x.${la("owner")} = adjust_leave_balance.user_id`};
  ${adjusted}
  return v_row;
end;
$$;
${userGrant(`${fn("adjust_leave_balance")}(${idType}, uuid, uuid, numeric, integer, text, text${employee ? ", uuid" : ""})`)}

-- Grants every member (or user_ids) an accrual of one type: amount, or the
-- type's allowance. With idempotency_key a member gets it once, so a
-- scheduled job can run it again safely. Returns how many entries it wrote.
${ownerDrop("accrue_leave", `${idType}, uuid, numeric, integer, uuid[], text, text`)}create or replace function ${fn("accrue_leave")}(tenant ${idType}, type_id uuid, amount numeric default null, period integer default null, user_ids uuid[] default null, idempotency_key text default null, note text default null${employee ? ", employee_ids uuid[] default null" : ""})
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_type ${types}%rowtype;
  v_amount numeric;
  v_user uuid;
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
  end if;
  for v_user in
${accrueOwners}
  loop
    continue when accrue_leave.idempotency_key is not null
      and ${fn("leave_posted")}(accrue_leave.tenant, v_user, v_type.${ty("id")}, accrue_leave.idempotency_key);
    perform ${fn("leave_post")}(accrue_leave.tenant, v_user, v_type.${ty("id")}, 'accrual', v_amount,
      coalesce(accrue_leave.period, extract(year from current_date)::integer), null, accrue_leave.note, accrue_leave.idempotency_key);
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
${userGrant(`${fn("accrue_leave")}(${idType}, uuid, numeric, integer, uuid[], text, text${employee ? ", uuid[]" : ""})`)}

-- Closes a period: each member's positive balance of each tracked type
-- carries into the next period up to the type's carryover_max, and the rest
-- expires. Run once per period; a second run writes nothing. Returns how
-- many entries on members' accounts it wrote.
create or replace function ${fn("close_leave_year")}(tenant ${idType}, period integer)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_column
declare
  v_key text := 'close:' || close_leave_year.period::text;
  v_row record;
  v_written integer := 0;
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "close_leave_year.tenant", manage)}) then
    ${forbidden("not allowed to close leave periods")}
  end if;
  if close_leave_year.period is null then
    ${invalid("name the period to close")}
  end if;
  for v_row in
    select ${employee ? `(x.${la("metadata")} ->> 'employeeId')::uuid` : `x.${la("owner")}`} as user_id, t.${ty("id")} as type_id, b.${lb("balance")}::numeric / ${SCALE} as balance,
      ${ctx.has("types", "carryoverMax") ? `least(b.${lb("balance")}::numeric / ${SCALE}, coalesce(t.${ty("carryoverMax")}, b.${lb("balance")}::numeric / ${SCALE}))` : `b.${lb("balance")}::numeric / ${SCALE}`} as carry
    from ${accounts} x
    join ${balances} b on b.${lb("account")} = x.${la("id")}
    join ${types} t on t.${ty("id")}::text = x.${la("holderId")} and t.${ty("tracked")}
    where x.${la("tenant")} = close_leave_year.tenant and x.${la("managedBy")} = 'leave' and x.${la("kind")} = 'leave'
      and (x.${la("metadata")} ->> 'period')::integer = close_leave_year.period and b.${lb("balance")} > 0
  loop
    if v_row.carry <> 0 and not ${fn("leave_posted")}(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':carryover:' || close_leave_year.period::text) then
      perform ${fn("leave_post")}(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'carryover', -v_row.carry, close_leave_year.period,
        null, null, v_key || ':carryover:' || close_leave_year.period::text, close_leave_year.period + 1);
      v_written := v_written + 2;
    end if;
    if v_row.balance - v_row.carry <> 0 and not ${fn("leave_posted")}(close_leave_year.tenant, v_row.user_id, v_row.type_id, v_key || ':expiry:' || close_leave_year.period::text) then
      perform ${fn("leave_post")}(close_leave_year.tenant, v_row.user_id, v_row.type_id, 'expiry', -(v_row.balance - v_row.carry), close_leave_year.period,
        null, null, v_key || ':expiry:' || close_leave_year.period::text);
      v_written := v_written + 1;
    end if;
  end loop;
  return v_written;
end;
$$;
${userGrant(`${fn("close_leave_year")}(${idType}, integer)`)}
`;
}

/** Copies `leave_ledger` into the ledger, keeping each row's id. */
export function leaveLedgerUpgrade(ctx: BlockSqlContext): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const ledger = ctx.of("ledger");
  const accounts = ledger.table("accounts");
  const la = (column: string): string => ledger.col("accounts", column);
  const lt = (column: string): string => ledger.col("transactions", column);
  const memo = ledger.has("transactions", "memo");
  const le = (column: string): string => ledger.col("entries", column);
  const read = ctx.permission("read", moduleOperations("leave").read);
  const types = ctx.table("types");
  const ty = (column: string): string => ctx.col("types", column);
  const old = `${ctx.schema}.leave_ledger`;
  // The old table took the tenant column the block names on its other tables.
  const mt = ctx.col("types", "tenant");

  const counter = (row: string): string =>
    `'leave:' || ${row}.type_id::text || case when ${row}.kind = 'taken' then ':taken' else ':pool' end`;

  return `${ledgerTables(ledger)}
do $upgrade$
begin
  if to_regclass('${ctx.schemaName}.leave_ledger') is null then
    return;
  end if;
  insert into ${accounts} (${la("tenant")}, ${la("kind")}, ${la("code")}, ${la("name")}, ${la("unit")}, ${la("scale")}, ${la("holderType")}, ${la("holderId")}, ${la("owner")}, ${la("allowNegative")}, ${la("readPermission")}, ${la("managedBy")}, ${la("metadata")})
  select distinct m.${mt}, 'leave', ${userCode("m.type_id", "m.user_id", "m.period")}, 'Leave', t.${ty("unit")}, 2, 'leave-types', m.type_id::text, m.user_id, true, ${read}, 'leave',
    jsonb_build_object('userId', m.user_id, 'typeId', m.type_id, 'period', m.period)
  from ${old} m join ${types} t on t.${ty("id")} = m.type_id
  on conflict do nothing;
  insert into ${accounts} (${la("tenant")}, ${la("kind")}, ${la("code")}, ${la("name")}, ${la("unit")}, ${la("scale")}, ${la("holderType")}, ${la("holderId")}, ${la("allowNegative")}, ${la("readPermission")}, ${la("managedBy")})
  select distinct m.${mt}, 'leave_pool', ${counter("m")}, case when m.kind = 'taken' then 'Leave taken' else 'Leave pool' end, t.${ty("unit")}, 2, 'leave-types', m.type_id::text, true, ${read}, 'leave'
  from ${old} m join ${types} t on t.${ty("id")} = m.type_id
  on conflict do nothing;
  insert into ${ledger.table("transactions")} (${lt("id")}, ${lt("tenant")}, ${lt("kind")}, ${lt("referenceType")}, ${lt("referenceId")}, ${memo ? `${lt("memo")}, ` : ""}${lt("key")}, ${lt("metadata")}, ${lt("effectiveAt")}, ${lt("actor")}, ${lt("createdAt")})
  select m.id, m.${mt}, 'leave.' || m.kind, case when m.request_id is not null then 'leave-requests' end, m.request_id::text,${memo ? " m.note," : ""}
    case when m.idempotency_key is not null then 'leave:' || m.user_id::text || ':' || m.type_id::text || ':' || m.idempotency_key end,
    jsonb_build_object('userId', m.user_id, 'typeId', m.type_id, 'period', m.period, 'kind', m.kind), m.created_at, m.created_by, m.created_at
  from ${old} m
  on conflict do nothing;
  insert into ${ledger.table("entries")} (${le("tenant")}, ${le("transaction")}, ${le("account")}, ${le("amount")}, ${le("unit")}, ${le("createdAt")})
  select m.${mt}, m.id, x.${la("id")}, round(m.amount * ${SCALE})::bigint, x.${la("unit")}, m.created_at
  from ${old} m join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${userCode("m.type_id", "m.user_id", "m.period")}
  union all
  select m.${mt}, m.id, x.${la("id")}, -round(m.amount * ${SCALE})::bigint, x.${la("unit")}, m.created_at
  from ${old} m join ${accounts} x on x.${la("tenant")} = m.${mt} and x.${la("code")} = ${counter("m")};
  ${ledgerRebalance(ledger)}
  drop table ${old};
end;
$upgrade$;`;
}
