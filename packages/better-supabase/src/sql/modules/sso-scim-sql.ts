import type { ModuleContext, ModuleContractFunction } from "../context.ts";

import { fail, lockTable, raise, serviceGrant } from "../shared.ts";
/** The SCIM storage functions of the sso module, for the SCIM handler. */

export interface ScimSqlNames {
  /** The tenant id type. */
  readonly id: string;
  readonly fn: (name: string) => string;
  readonly users: string;
  readonly groups: string;
  readonly members: string;
  readonly cu: (column: string) => string;
  readonly cg: (column: string) => string;
  readonly cm: (column: string) => string;
  /** Raises unless the caller is the service role. */
  readonly serviceOnly: (what: string) => string;
  /** Whether the email's domain is verified for the tenant. */
  readonly verifiedFor: (tenant: string, email: string) => string;
  /** Records a SCIM write: `ctx.record` with the tenant and the row's id. */
  readonly record: (type: string, tenant: string, id: string) => string;
}

export function scimSql(names: ScimSqlNames): string {
  const { id, fn, cu, cg, cm, serviceOnly, verifiedFor, record } = names;
  const u = names.users;
  const g = names.groups;
  const gm = names.members;
  const userJson = (alias: string): string =>
    `to_jsonb(${alias}.*) || jsonb_build_object('groups', (
      select coalesce(jsonb_agg(jsonb_build_object('value', sg.${cg("id")}, 'display', sg.${cg("displayName")}) order by sg.${cg("displayName")}), '[]'::jsonb)
      from ${gm} sm join ${g} sg on sg.${cg("id")} = sm.${cm("group")}
      where sm.${cm("member")} = ${alias}.${cu("id")}
    ))`;
  const groupJson = (alias: string): string =>
    `to_jsonb(${alias}.*) || jsonb_build_object('members', (
      select coalesce(jsonb_agg(jsonb_build_object('value', su.${cu("id")}, 'display', coalesce(su.${cu("displayName")}, su.${cu("userName")})) order by su.${cu("userName")}), '[]'::jsonb)
      from ${gm} sm join ${u} su on su.${cu("id")} = sm.${cm("member")}
      where sm.${cm("group")} = ${alias}.${cg("id")}
    ))`;
  return `-- SCIM storage for the SCIM handler (service role). Rows come back as
-- jsonb; users carry their groups and groups their members.
create or replace function ${fn("scim_list_users")}(tenant ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select coalesce(jsonb_agg(${userJson("x")} order by x.${cu("createdAt")}, x.${cu("id")}), '[]'::jsonb)
    from ${u} x where x.${cu("tenant")} = scim_list_users.tenant
  );
end;
$$;

create or replace function ${fn("scim_get_user")}(tenant ${id}, id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select ${userJson("x")} from ${u} x
    where x.${cu("tenant")} = scim_get_user.tenant and x.${cu("id")} = scim_get_user.id
  );
end;
$$;

-- Creates (id null) or replaces a SCIM user. \`version\`, when set, must
-- match (If-Match). data: { userName, externalId, displayName, givenName,
-- familyName, emails, active }.
create or replace function ${fn("scim_save_user")}(tenant ${id}, id uuid, data jsonb, version integer default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row ${u};
  v_emails jsonb := coalesce(scim_save_user.data -> 'emails', '[]'::jsonb);
  v_name text := scim_save_user.data ->> 'userName';
  v_email text;
  v_user uuid;
begin
  ${serviceOnly("serves SCIM")}
  if v_name is null or length(trim(v_name)) = 0 then
    ${fail("SCIM_INVALID", "userName is required", "22023")}
  end if;
  if jsonb_typeof(v_emails) <> 'array' then
    ${fail("SCIM_INVALID", "emails must be an array", "22023")}
  end if;
  v_email := lower(coalesce(
    (select e ->> 'value' from jsonb_array_elements(v_emails) e where (e ->> 'primary')::boolean limit 1),
    v_emails -> 0 ->> 'value',
    case when v_name like '%@%' then v_name end
  ));
  if scim_save_user.id is null then
    insert into ${u} (${cu("tenant")}, ${cu("externalId")}, ${cu("userName")}, ${cu("displayName")}, ${cu("givenName")}, ${cu("familyName")}, ${cu("email")}, ${cu("emails")}, ${cu("active")})
    values (scim_save_user.tenant, scim_save_user.data ->> 'externalId', v_name, scim_save_user.data ->> 'displayName',
      scim_save_user.data ->> 'givenName', scim_save_user.data ->> 'familyName', v_email, v_emails,
      coalesce((scim_save_user.data ->> 'active')::boolean, true))
    returning * into v_row;
  else
    select * into v_row from ${u} x where x.${cu("tenant")} = scim_save_user.tenant and x.${cu("id")} = scim_save_user.id for update;
    if v_row.${cu("id")} is null then
      ${fail("SCIM_NOT_FOUND", "No SCIM user has this id", "P0002")}
    end if;
    if scim_save_user.version is not null and scim_save_user.version <> v_row.${cu("version")} then
      ${raise("The user changed since version %", "P0001", "SCIM_PRECONDITION", "scim_save_user.version")}
    end if;
    update ${u} x set
      ${cu("externalId")} = scim_save_user.data ->> 'externalId',
      ${cu("userName")} = v_name,
      ${cu("displayName")} = scim_save_user.data ->> 'displayName',
      ${cu("givenName")} = scim_save_user.data ->> 'givenName',
      ${cu("familyName")} = scim_save_user.data ->> 'familyName',
      ${cu("email")} = v_email,
      ${cu("emails")} = v_emails,
      ${cu("active")} = coalesce((scim_save_user.data ->> 'active')::boolean, true),
      ${cu("version")} = x.${cu("version")} + 1,
      ${cu("updatedAt")} = now()
    where x.${cu("id")} = v_row.${cu("id")}
    returning * into v_row;
  end if;
  if v_row.${cu("user")} is null and v_email is not null and ${verifiedFor("scim_save_user.tenant", "v_email")} then
    select au.id into v_user from auth.users au
    where lower(au.email) = v_email and au.email_confirmed_at is not null
      and not exists (select 1 from ${u} y where y.${cu("tenant")} = scim_save_user.tenant and y.${cu("user")} = au.id)
    limit 1;
    if v_user is not null then
      update ${u} x set ${cu("user")} = v_user where x.${cu("id")} = v_row.${cu("id")} returning * into v_row;
    end if;
  end if;
  perform ${fn("scim_sync_member")}(v_row.${cu("id")});
  ${record("scim_user.saved", "scim_save_user.tenant", `v_row.${cu("id")}`)}
  return (select ${userJson("x")} from ${u} x where x.${cu("id")} = v_row.${cu("id")});
end;
$$;

-- Deprovisions (removes the membership) and deletes a SCIM user.
create or replace function ${fn("scim_delete_user")}(tenant ${id}, id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_id uuid;
begin
  ${serviceOnly("serves SCIM")}
  update ${u} x set ${cu("active")} = false
  where x.${cu("tenant")} = scim_delete_user.tenant and x.${cu("id")} = scim_delete_user.id
  returning x.${cu("id")} into v_id;
  if v_id is null then
    return false;
  end if;
  perform ${fn("scim_sync_member")}(v_id);
  delete from ${u} x where x.${cu("id")} = v_id;
  ${record("scim_user.deleted", "scim_delete_user.tenant", "v_id")}
  return true;
end;
$$;

create or replace function ${fn("scim_list_groups")}(tenant ${id})
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select coalesce(jsonb_agg(${groupJson("x")} order by x.${cg("createdAt")}, x.${cg("id")}), '[]'::jsonb)
    from ${g} x where x.${cg("tenant")} = scim_list_groups.tenant
  );
end;
$$;

create or replace function ${fn("scim_get_group")}(tenant ${id}, id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("serves SCIM")}
  return (
    select ${groupJson("x")} from ${g} x
    where x.${cg("tenant")} = scim_get_group.tenant and x.${cg("id")} = scim_get_group.id
  );
end;
$$;

-- Creates (id null) or replaces a group and its members, then syncs the
-- roles of everyone who joined or left. data: { displayName, externalId,
-- members: [scim user id] }.
create or replace function ${fn("scim_save_group")}(tenant ${id}, id uuid, data jsonb, version integer default null)
returns jsonb
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_row ${g};
  v_name text := scim_save_group.data ->> 'displayName';
  v_members uuid[];
  v_before uuid[] := '{}';
  v_member uuid;
begin
  ${serviceOnly("serves SCIM")}
  if v_name is null or length(trim(v_name)) = 0 then
    ${fail("SCIM_INVALID", "displayName is required", "22023")}
  end if;
  begin
    select coalesce(array_agg(distinct (w.value)::uuid), '{}') into v_members
    from jsonb_array_elements_text(coalesce(scim_save_group.data -> 'members', '[]'::jsonb)) w;
  exception when invalid_text_representation then
    ${fail("SCIM_INVALID", "members must be SCIM user ids", "22023")}
  end;
  if exists (
    select 1 from unnest(v_members) w(member)
    where not exists (select 1 from ${u} x where x.${cu("tenant")} = scim_save_group.tenant and x.${cu("id")} = w.member)
  ) then
    ${fail("SCIM_INVALID", "members must be SCIM users of the organization", "22023")}
  end if;
  if scim_save_group.id is null then
    insert into ${g} (${cg("tenant")}, ${cg("displayName")}, ${cg("externalId")}, ${cg("role")})
    values (scim_save_group.tenant, v_name, scim_save_group.data ->> 'externalId', ${fn("scim_group_role")}(v_name))
    returning * into v_row;
  else
    select * into v_row from ${g} x where x.${cg("tenant")} = scim_save_group.tenant and x.${cg("id")} = scim_save_group.id for update;
    if v_row.${cg("id")} is null then
      ${fail("SCIM_NOT_FOUND", "No SCIM group has this id", "P0002")}
    end if;
    if scim_save_group.version is not null and scim_save_group.version <> v_row.${cg("version")} then
      ${raise("The group changed since version %", "P0001", "SCIM_PRECONDITION", "scim_save_group.version")}
    end if;
    select coalesce(array_agg(sm.${cm("member")}), '{}') into v_before from ${gm} sm where sm.${cm("group")} = v_row.${cg("id")};
    update ${g} x set
      ${cg("displayName")} = v_name,
      ${cg("externalId")} = scim_save_group.data ->> 'externalId',
      ${cg("role")} = ${fn("scim_group_role")}(v_name),
      ${cg("version")} = x.${cg("version")} + 1,
      ${cg("updatedAt")} = now()
    where x.${cg("id")} = v_row.${cg("id")}
    returning * into v_row;
    delete from ${gm} sm where sm.${cm("group")} = v_row.${cg("id")} and not (sm.${cm("member")} = any (v_members));
  end if;
  insert into ${gm} (${cm("group")}, ${cm("member")})
  select v_row.${cg("id")}, w.member from unnest(v_members) w(member)
  on conflict do nothing;
  for v_member in select distinct w.member from unnest(v_before || v_members) w(member) loop
    perform ${fn("scim_sync_member")}(v_member);
  end loop;
  ${record("scim_group.saved", "scim_save_group.tenant", `v_row.${cg("id")}`)}
  return (select ${groupJson("x")} from ${g} x where x.${cg("id")} = v_row.${cg("id")});
end;
$$;

create or replace function ${fn("scim_delete_group")}(tenant ${id}, id uuid)
returns boolean
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_members uuid[];
  v_member uuid;
begin
  ${serviceOnly("serves SCIM")}
  select coalesce(array_agg(sm.${cm("member")}), '{}') into v_members
  from ${gm} sm join ${g} x on x.${cg("id")} = sm.${cm("group")}
  where x.${cg("tenant")} = scim_delete_group.tenant and x.${cg("id")} = scim_delete_group.id;
  delete from ${g} x where x.${cg("tenant")} = scim_delete_group.tenant and x.${cg("id")} = scim_delete_group.id;
  if not found then
    return false;
  end if;
  foreach v_member in array v_members loop
    perform ${fn("scim_sync_member")}(v_member);
  end loop;
  ${record("scim_group.deleted", "scim_delete_group.tenant", "scim_delete_group.id")}
  return true;
end;
$$;`;
}

const SCIM_SYNC_LOG = "better_supabase.scim_sync_log";

export const SCIM_SYNC_LOG_CONTRACT: readonly ModuleContractFunction[] = [
  {
    name: "scim_log_sync",
    args: ["{id}", "text", "text", "text", "integer", "text", "text"],
    returns: "void",
  },
  { name: "list_scim_sync_log", args: ["{id}", "integer"], returns: "jsonb" },
  {
    name: "purge_scim_sync_log",
    args: ["interval", "integer"],
    returns: "integer",
  },
];

/** `blocks.sso.options.syncLog`: one row per SCIM write, for the handler's log. */
export function scimSyncLogSql(
  ctx: ModuleContext,
  serviceOnly: (what: string) => string,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  return `-- One row per SCIM write: what the identity provider asked for and how it
-- went. sqlScimSyncLog writes it through scim_log_sync.
create table if not exists ${SCIM_SYNC_LOG} (
  id bigint generated always as identity primary key,
  organization_id ${id} not null,
  operation text not null check (operation in ('create', 'replace', 'patch', 'delete')),
  resource_type text not null check (resource_type in ('User', 'Group')),
  resource_id text,
  status integer not null,
  error text,
  request_id text,
  created_at timestamptz not null default now()
);
create index if not exists scim_sync_log_tenant_idx on ${SCIM_SYNC_LOG} (organization_id, created_at desc);
create index if not exists scim_sync_log_created_idx on ${SCIM_SYNC_LOG} (created_at);
${lockTable(SCIM_SYNC_LOG)}

create or replace function ${fn("scim_log_sync")}(
  tenant ${id},
  operation text,
  resource_type text,
  resource_id text default null,
  status integer default null,
  error text default null,
  request_id text default null
)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("logs SCIM writes")}
  insert into ${SCIM_SYNC_LOG} (organization_id, operation, resource_type, resource_id, status, error, request_id)
  values (scim_log_sync.tenant, scim_log_sync.operation, scim_log_sync.resource_type, scim_log_sync.resource_id,
    coalesce(scim_log_sync.status, 0), left(scim_log_sync.error, 2000), left(scim_log_sync.request_id, 200));
end;
$$;

-- The tenant's latest SCIM writes, newest first.
create or replace function ${fn("list_scim_sync_log")}(tenant ${id}, max integer default 100)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  ${serviceOnly("reads the SCIM log")}
  return (
    select coalesce(jsonb_agg(to_jsonb(x) order by x.created_at desc, x.id desc), '[]'::jsonb)
    from (
      select * from ${SCIM_SYNC_LOG} l
      where l.organization_id = list_scim_sync_log.tenant
      order by l.created_at desc, l.id desc
      limit least(greatest(coalesce(list_scim_sync_log.max, 100), 1), 1000)
    ) x
  );
end;
$$;

-- Deletes log rows older than older_than (or the data-lifecycle policy),
-- at most batch.
create or replace function ${fn("purge_scim_sync_log")}(older_than interval default '90 days', batch integer default 10000)
returns integer
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_count integer;
begin
  ${serviceOnly("purges the SCIM log")}
  delete from ${SCIM_SYNC_LOG} l where l.id in (
    select x.id from ${SCIM_SYNC_LOG} x
    where ${ctx.expired("scim_sync_log", { at: "x.created_at", tenant: "x.organization_id", fallback: "coalesce(older_than, interval '90 days')" })}
    limit greatest(coalesce(batch, 10000), 1)
  );
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
${serviceGrant(`${fn("scim_log_sync")}(${id}, text, text, text, integer, text, text)`)}
${serviceGrant(`${fn("list_scim_sync_log")}(${id}, integer)`)}
${serviceGrant(`${fn("purge_scim_sync_log")}(interval, integer)`)}`;
}
