import type { BlockSqlContext } from "../context.ts";

import { pageSize, userGrant } from "../shared.ts";
import { tillsSql } from "./tills-sql.ts";

export function tillsFunctions(ctx: BlockSqlContext): string {
  const sql = tillsSql(ctx);
  const { fn, t, s, tills, sessions } = sql;
  const idType = ctx.idType;

  // The cash account must exist for the tenant when accounting is installed.
  const accountCheck = (account: string, tenant: string): string =>
    sql.accounting === undefined
      ? ""
      : `
  if ${account} is not null and not exists (select 1 from ${sql.accounting.table("accounts")} a
    where a.${sql.accounting.col("accounts", "id")} = ${account} and a.${sql.accounting.col("accounts", "tenant")} = ${tenant}) then
    ${sql.invalid("accountId is not an account of the organization")}
  end if;`;

  return `
-- Creates a till. input is { name, currency, accountId, location }; accountId
-- is the accounting account that holds its cash. Needs tills.manage.
create or replace function ${fn("create_till")}(tenant ${idType}, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(create_till.input, '{}'::jsonb);
  v_account uuid;
  v_row ${tills};
begin
  if not ${sql.allowed("create_till.tenant", sql.manage)} then
    ${sql.forbidden("not allowed to create tills")}
  end if;
  if coalesce(trim(v_input ->> 'name'), '') = '' or coalesce(v_input ->> 'currency', '') !~ '^[A-Z]{3}$' then
    ${sql.invalid("a till needs a name and an ISO 4217 currency such as EUR")}
  end if;
  if coalesce(v_input ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
    v_account := (v_input ->> 'accountId')::uuid;
  elsif nullif(v_input ->> 'accountId', '') is not null then
    ${sql.invalid("accountId is a uuid")}
  end if;${accountCheck("v_account", "create_till.tenant")}
  begin
    insert into ${tills} (${t("tenant")}, ${t("name")}, ${t("currency")}, ${t("account")}, ${t("location")})
    values (create_till.tenant, trim(v_input ->> 'name'), v_input ->> 'currency', v_account, nullif(trim(v_input ->> 'location'), ''))
    returning * into v_row;
  exception when unique_violation then
    ${sql.invalid("a till with this name exists")}
  when check_violation then
    ${sql.invalid("a till needs a name of up to 100 characters and a location of up to 200")}
  end;
  ${sql.recordTill("till.created", "v_row", "till created")}
  return ${sql.tillJson("v_row")};
end;
$$;
${userGrant(`${fn("create_till")}(${idType}, jsonb)`)}

-- Changes a till. input may hold name, accountId, location and archived (true
-- archives it, false brings it back). An archived till opens no sessions and a
-- till with an open session cannot be archived. The currency never changes.
-- Needs tills.manage.
create or replace function ${fn("update_till")}(till_id uuid, input jsonb)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_input jsonb := coalesce(update_till.input, '{}'::jsonb);
  v_row ${tills};
  v_account uuid;
begin
  select * into v_row from ${tills} x where x.${t("id")} = update_till.till_id for update;
  if not found or not ${sql.allowed(`v_row.${t("tenant")}`, sql.read)} then
    ${sql.tillMissing}
  end if;
  if not ${sql.allowed(`v_row.${t("tenant")}`, sql.manage)} then
    ${sql.forbidden("not allowed to change tills")}
  end if;
  if v_input ? 'name' and coalesce(trim(v_input ->> 'name'), '') = '' then
    ${sql.invalid("a till needs a name")}
  end if;
  v_account := v_row.${t("account")};
  if v_input ? 'accountId' then
    if coalesce(v_input ->> 'accountId', '') ~ '^[0-9a-fA-F-]{36}$' then
      v_account := (v_input ->> 'accountId')::uuid;
    elsif v_input -> 'accountId' = 'null'::jsonb then
      v_account := null;
    else
      ${sql.invalid("accountId is a uuid or null")}
    end if;
  end if;${accountCheck("v_account", `v_row.${t("tenant")}`)}
  if v_input ->> 'archived' = 'true' and exists (select 1 from ${sessions} y where y.${s("till")} = v_row.${t("id")} and y.${s("status")} = 'open') then
    ${sql.status("close the open session before archiving the till")}
  end if;
  begin
    update ${tills} x set
      ${t("name")} = case when v_input ? 'name' then trim(v_input ->> 'name') else x.${t("name")} end,
      ${t("account")} = v_account,
      ${t("location")} = case when v_input ? 'location' then nullif(trim(v_input ->> 'location'), '') else x.${t("location")} end,
      ${t("archivedAt")} = case when v_input ->> 'archived' = 'true' then coalesce(x.${t("archivedAt")}, now())
        when v_input ->> 'archived' = 'false' then null else x.${t("archivedAt")} end,
      ${t("updatedAt")} = now()
    where x.${t("id")} = v_row.${t("id")}
    returning * into v_row;
  exception when unique_violation then
    ${sql.invalid("a till with this name exists")}
  when check_violation then
    ${sql.invalid("a till needs a name of up to 100 characters and a location of up to 200")}
  end;
  ${sql.recordTill("till.updated", "v_row", "till changed")}
  return ${sql.tillJson("v_row")};
end;
$$;
${userGrant(`${fn("update_till")}(uuid, jsonb)`)}

-- Tills by name. filters is { archived } (true lists archived ones too).
create or replace function ${fn("list_tills")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_tills.filters, '{}'::jsonb);
begin
  if not ${sql.allowed("list_tills.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read tills")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.tillJson("y")} order by y.${t("name")})
    from ${tills} y
    where y.${t("tenant")} = list_tills.tenant
      and (v_filters ->> 'archived' = 'true' or y.${t("archivedAt")} is null)
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_tills")}(${idType}, jsonb)`)}

-- Starts a shift at a till with the cash in the drawer (opening_float, minor
-- units). A till has one open session at a time. Needs tills.write.
create or replace function ${fn("open_till_session")}(till_id uuid, opening_float bigint default 0, notes text default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_till ${tills};
  v_row ${sessions};
begin
  select * into v_till from ${tills} x where x.${t("id")} = open_till_session.till_id for update;
  if not found or not ${sql.allowed(`v_till.${t("tenant")}`, sql.read)} then
    ${sql.tillMissing}
  end if;
  if not ${sql.allowed(`v_till.${t("tenant")}`, sql.write)} then
    ${sql.forbidden("not allowed to open till sessions")}
  end if;
  if v_till.${t("archivedAt")} is not null then
    ${sql.status("an archived till opens no sessions")}
  end if;
  if coalesce(open_till_session.opening_float, 0) < 0 then
    ${sql.invalid("the opening float is zero or more")}
  end if;
  ${ctx.hook("before_till_session_open", [
    ["uuid", `v_till.${t("id")}`],
    ["bigint", "coalesce(open_till_session.opening_float, 0)"],
  ])}
  begin
    insert into ${sessions} (${s("tenant")}, ${s("till")}, ${s("openingFloat")}, ${s("openedBy")}, ${s("notes")})
    values (v_till.${t("tenant")}, v_till.${t("id")}, coalesce(open_till_session.opening_float, 0), auth.uid(), nullif(trim(open_till_session.notes), ''))
    returning * into v_row;
  exception when unique_violation then
    ${sql.status("this till already has an open session")}
  when check_violation then
    ${sql.invalid("notes are up to 2000 characters")}
  end;
  ${sql.recordSession("till_session.opened", "v_row", "v_till", "till session opened")}
  ${ctx.hook("after_till_session_open", [["uuid", `v_row.${s("id")}`]])}
  return ${sql.sessionJson("v_row")};
end;
$$;
${userGrant(`${fn("open_till_session")}(uuid, bigint, text)`)}

-- A session with its movements, its count and its deposits.
create or replace function ${fn("get_till_session")}(session_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${sessions};
begin
  select * into v_row from ${sessions} x where x.${s("id")} = get_till_session.session_id;
  if not found or not ${sql.allowed(`v_row.${s("tenant")}`, sql.read)} then
    ${sql.sessionMissing}
  end if;
  return ${sql.sessionDetail("v_row")};
end;
$$;
${userGrant(`${fn("get_till_session")}(uuid)`)}

-- Sessions, newest first. filters is { tillId, status, limit, offset }.
create or replace function ${fn("list_till_sessions")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_till_sessions.filters, '{}'::jsonb);
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
begin
  if not ${sql.allowed("list_till_sessions.tenant", sql.read)} then
    ${sql.forbidden("not allowed to read till sessions")}
  end if;
  return coalesce((
    select jsonb_agg(${sql.sessionJson("y")} order by y.${s("openedAt")} desc, y.${s("id")})
    from (
      select * from ${sessions} x
      where x.${s("tenant")} = list_till_sessions.tenant
        and (not v_filters ? 'tillId' or x.${s("till")}::text = v_filters ->> 'tillId')
        and (not v_filters ? 'status' or x.${s("status")} = v_filters ->> 'status')
      order by x.${s("openedAt")} desc, x.${s("id")}
      limit v_limit offset coalesce((v_filters ->> 'offset')::integer, 0)
    ) y
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("list_till_sessions")}(${idType}, jsonb)`)}
`;
}
