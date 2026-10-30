import type { BlockSqlContext, BlockSqlContractFunction } from "../context.ts";

import { createdOrUpdated } from "../event-verbs.ts";
import { fail, lockTable, raise, serviceGrant } from "../shared.ts";

/**
 * A row of an sso table as jsonb keyed by the default column names, built
 * column by column so the other columns of the app's table stay out. A column
 * the table lacks reads as `missing[logical]`, else null.
 */
export function appRowJson(
  ctx: BlockSqlContext,
  table: string,
  row: string,
  missing: Readonly<Record<string, string>>,
  omit: readonly string[],
): string {
  const columns = ctx.names.tables[table]?.columns ?? {};

  const pairs = Object.entries(columns)
    .filter(([logical]) => !omit.includes(logical))
    .map(
      ([logical, name]) =>
        `'${name}', ${ctx.has(table, logical) ? `${row}.${ctx.col(table, logical)}` : (missing[logical] ?? "null")}`,
    );

  return `jsonb_build_object(${pairs.join(", ")})`;
}

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
  /** A SCIM user or group row as jsonb, without the members or groups. */
  readonly row: (table: "scimUsers" | "scimGroups", alias: string) => string;
  /** Whether the logical column of the SCIM users or groups table exists. */
  readonly has: (table: "scimUsers" | "scimGroups", column: string) => boolean;
  /** A group's role written as the role column's type. */
  readonly role: (value: string) => string;
}

export function scimSql(names: ScimSqlNames): string {
  const { id, fn, cu, cg, cm, serviceOnly, verifiedFor, record, row, has } =
    names;

  const u = names.users;
  const g = names.groups;
  const gm = names.members;

  const shown = has("scimUsers", "displayName");

  const parts = ["givenName", "familyName"].filter((part) =>
    has("scimUsers", part),
  );

  const nameColumns = [...(shown ? ["displayName"] : []), ...parts]
    .map((part) => `, ${cu(part)}`)
    .join("");

  const userJson = (alias: string): string =>
    `${row("scimUsers", alias)} || jsonb_build_object('groups', (
      select coalesce(jsonb_agg(jsonb_build_object('value', sg.${cg("id")}, 'display', sg.${cg("displayName")}) order by sg.${cg("displayName")}), '[]'::jsonb)
      from ${gm} sm join ${g} sg on sg.${cg("id")} = sm.${cm("group")}
      where sm.${cm("member")} = ${alias}.${cu("id")}
    ))`;

  const groupJson = (alias: string): string =>
    `${row("scimGroups", alias)} || jsonb_build_object('members', (
      select coalesce(jsonb_agg(jsonb_build_object('value', su.${cu("id")}, 'display', ${has("scimUsers", "displayName") ? `coalesce(su.${cu("displayName")}, su.${cu("userName")})` : `su.${cu("userName")}`}) order by su.${cu("userName")}), '[]'::jsonb)
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
    insert into ${u} (${cu("tenant")}, ${cu("externalId")}, ${cu("userName")}${nameColumns}, ${cu("email")}, ${cu("emails")}, ${cu("active")})
    values (scim_save_user.tenant, scim_save_user.data ->> 'externalId', v_name${shown ? ", scim_save_user.data ->> 'displayName'" : ""},
      ${parts.map((part) => `scim_save_user.data ->> '${part}', `).join("")}v_email, v_emails,
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
      ${[
        `${cu("externalId")} = scim_save_user.data ->> 'externalId'`,
        `${cu("userName")} = v_name`,
        ...[...(shown ? ["displayName"] : []), ...parts].map(
          (part) => `${cu(part)} = scim_save_user.data ->> '${part}'`,
        ),
        `${cu("email")} = v_email`,
        `${cu("emails")} = v_emails`,
        `${cu("active")} = coalesce((scim_save_user.data ->> 'active')::boolean, true)`,
        `${cu("version")} = x.${cu("version")} + 1`,
        ...(has("scimUsers", "updatedAt")
          ? [`${cu("updatedAt")} = now()`]
          : []),
      ].join(",\n      ")}
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
  ${createdOrUpdated("scim_save_user.id is null", (verb) => record(`scim_user.${verb}`, "scim_save_user.tenant", `v_row.${cu("id")}`))}
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
    values (scim_save_group.tenant, v_name, scim_save_group.data ->> 'externalId', ${names.role(`${fn("scim_group_role")}(v_name)`)})
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
      ${cg("role")} = ${names.role(`${fn("scim_group_role")}(v_name)`)},
      ${cg("version")} = x.${cg("version")} + 1${has("scimGroups", "updatedAt") ? `,\n      ${cg("updatedAt")} = now()` : ""}
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
  ${createdOrUpdated("scim_save_group.id is null", (verb) => record(`scim_group.${verb}`, "scim_save_group.tenant", `v_row.${cg("id")}`))}
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

export const SCIM_SYNC_LOG_CONTRACT: readonly BlockSqlContractFunction[] = [
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
  ctx: BlockSqlContext,
  serviceOnly: (what: string) => string,
): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const log = ctx.table("syncLog");
  const { name } = ctx.tableName("syncLog");
  const c = (column: string): string => ctx.col("syncLog", column);
  const has = (column: string): boolean => ctx.has("syncLog", column);

  const line = (column: string): string =>
    has(column) ? `  ${c(column)} text,\n` : "";

  const columns: [string, string][] = [
    ["tenant", "scim_log_sync.tenant"],
    ["operation", ctx.cast("syncLog", "operation", "scim_log_sync.operation")],
    [
      "resourceType",
      ctx.cast("syncLog", "resourceType", "scim_log_sync.resource_type"),
    ],
    ["resourceId", "scim_log_sync.resource_id"],
    ["status", "coalesce(scim_log_sync.status, 0)"],
    ["error", "left(scim_log_sync.error, 2000)"],
    ["requestId", "left(scim_log_sync.request_id, 200)"],
  ];

  const written = columns.filter(([column]) => has(column));

  const read = (column: string): string =>
    has(column) ? `l.${c(column)}` : "null::text";

  return `-- One row per SCIM write: what the identity provider asked for and how it
-- went. sqlScimSyncLog writes it through scim_log_sync.
create table if not exists ${log} (
  ${c("id")} bigint generated always as identity primary key,
  ${c("tenant")} ${id} not null,
  ${c("operation")} text not null check (${c("operation")} in ('create', 'replace', 'patch', 'delete')),
  ${c("resourceType")} text not null check (${c("resourceType")} in ('User', 'Group')),
  ${c("resourceId")} text,
  ${c("status")} integer not null,
${line("error")}${line("requestId")}  ${c("createdAt")} timestamptz not null default now()
);
create index if not exists ${name}_tenant_idx on ${log} (${c("tenant")}, ${c("createdAt")} desc);
create index if not exists ${name}_created_idx on ${log} (${c("createdAt")});
${lockTable(log)}

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
  insert into ${log} (${written.map(([column]) => c(column)).join(", ")})
  values (${written.map(([, value]) => value).join(", ")});
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
      select l.${c("id")} as id, l.${c("tenant")} as organization_id, l.${c("operation")} as operation,
        l.${c("resourceType")} as resource_type, l.${c("resourceId")} as resource_id, l.${c("status")} as status,
        ${read("error")} as error, ${read("requestId")} as request_id, l.${c("createdAt")} as created_at
      from ${log} l
      where l.${c("tenant")} = list_scim_sync_log.tenant
      order by l.${c("createdAt")} desc, l.${c("id")} desc
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
  delete from ${log} l where l.${c("id")} in (
    select x.${c("id")} from ${log} x
    where ${ctx.expired("scim_sync_log", { at: `x.${c("createdAt")}`, tenant: `x.${c("tenant")}`, fallback: "coalesce(older_than, interval '90 days')" })}
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
