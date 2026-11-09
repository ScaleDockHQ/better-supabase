import type { TeamsEvents } from "../../blocks/teams/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import {
  extraFieldsArg,
  extraFieldsJson,
  fail,
  insertExtraColumns,
  lockTable,
  schemaPreamble,
  triggerGrant,
  userGrant,
  writeExtraColumns,
} from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";
import { providerTeamIds } from "./team-ids.ts";

const EVENTS: BlockSqlEvents<TeamsEvents> = {
  "team.created": {
    subject: "teams",
    payload: ["organizationId", "id", "name"],
  },
  "team.updated": {
    subject: "teams",
    payload: ["organizationId", "id", "name"],
  },
  "team.archived": { subject: "teams", payload: ["organizationId", "id"] },
  "team.restored": { subject: "teams", payload: ["organizationId", "id"] },
  "team.deleted": { subject: "teams", payload: ["organizationId", "id"] },
  "team_member.added": {
    subject: "teams",
    payload: ["organizationId", "id", "userId"],
  },
  "team_member.deleted": {
    subject: "teams",
    payload: ["organizationId", "id", "userId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: { team: { table: "teams", singular: "team", primary: true } },
  events: EVENTS,
  hooks: ["before_team_create", "after_team_create"],
  options: ["teamIdType", "patch", "restore"],
  tables: {
    teams: {
      name: "teams",
      app: {},
      lifecycle: { tenant: "tenant", user: "createdBy", export: true },
      columns: {
        id: "id",
        tenant: "tenant_id",
        name: "name",
        slug: "slug",
        description: "description",
        status: "status",
        createdBy: "created_by",
        createdAt: "created_at",
        updatedAt: "updated_at",
      },
    },
    members: {
      name: "team_members",
      app: { unused: (ctx) => (employeeMembers(ctx) ? [] : ["employee"]) },
      lifecycle: { tenant: "tenant", user: "user", export: true },
      optional: ["employee"],
      columns: {
        team: "team_id",
        user: "user_id",
        employee: "employee_id",
        tenant: "tenant_id",
        createdAt: "created_at",
      },
    },
  },
};

const SLUG = "'^[a-z0-9]+(-[a-z0-9]+)*$'";

/** The keys the team reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

export function teamIdType(ctx: BlockSqlContext): "uuid" | "bigint" {
  const value = ctx.option("teamIdType") ?? "uuid";

  if (value !== "uuid" && value !== "bigint") {
    throw new TypeError(
      'blocks.teams.options.teamIdType must be "uuid" or "bigint"',
    );
  }

  if (ctx.installed("inbox") && value !== "uuid") {
    throw new TypeError(
      "inbox assigns teams by uuid. Leave blocks.teams.options.teamIdType unset, or do not install inbox.",
    );
  }

  return value;
}

function build(ctx: BlockSqlContext, layout: BlockSqlLayout): string {
  if (ctx.mode === "custom") {
    return "";
  }

  const idType = teamIdType(ctx);
  const teams = ctx.table("teams");
  const members = ctx.table("members");
  const id = ctx.col("teams", "id");
  const tenant = ctx.col("teams", "tenant");
  const name = ctx.col("teams", "name");
  const slug = ctx.col("teams", "slug");
  const description = ctx.col("teams", "description");
  const status = ctx.col("teams", "status");
  const createdBy = ctx.col("teams", "createdBy");
  const createdAt = ctx.col("teams", "createdAt");
  const updatedAt = ctx.col("teams", "updatedAt");
  const memberTeam = ctx.col("members", "team");
  const memberUser = ctx.col("members", "user");
  const memberTenant = ctx.col("members", "tenant");
  const memberCreated = ctx.col("members", "createdAt");
  const manage = ctx.permissionKey("manage", OPERATIONS["teams.manage"]);

  const key = (action: string): string =>
    sqlString(ctx.config.permissions[action] ?? manage);

  const create = key("create");
  const update = key("update");
  const remove = key("delete");
  const membersKey = key("members");
  const read = ctx.permission("read", OPERATIONS["teams.read"]);
  const extras = ctx.extraColumns("teams", RESERVED);
  const extra = extraFieldsArg(extras);
  const required = insertExtraColumns(teams, extras, "create_team.fields");
  const patching = ctx.flag("patch", false);
  const restoring = ctx.flag("restore", false);

  const derivedSlug =
    "trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'))";

  const drops = (fn: string, head: string, tails: readonly string[]) =>
    tails
      .map((tail) => `drop function if exists ${fn}(${head}${tail});`)
      .join("\n");

  const teamJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${id}, 'name', ${alias}.${name}, 'slug', ${alias}.${slug}, 'description', ${alias}.${description}, 'status', ${alias}.${status}${extraFieldsJson(alias, extras)})`;

  const idDefault =
    idType === "uuid"
      ? " default gen_random_uuid()"
      : " generated always as identity";

  const employees = employeeMembers(ctx);

  const tables = ctx.manages
    ? `create table if not exists ${teams} (
  ${id} ${idType} primary key${idDefault},
  ${tenant} ${ctx.idType} not null,
  ${name} text not null check (length(${name}) between 1 and 200),
  ${slug} text not null check (${slug} ~ '^[a-z0-9]+(?:-[a-z0-9]+)*$'),
  ${description} text,
  ${status} text not null default 'active' check (${status} in ('active', 'archived')),
  ${createdBy} uuid,
  ${createdAt} timestamptz not null default now(),
  ${updatedAt} timestamptz not null default now(),
  unique (${tenant}, ${slug})
);
${lockTable(teams, { read: true })}
${renderPolicy(makePolicy({ table: teams, name: ctx.naming.rename("teams_read"), command: "select", roles: ["authenticated"], using: `${tenant} in (select ${ctx.scope.ids(read)})` }), { target: teams })}

${
  employees
    ? employeeMembersTable(ctx, idType)
    : `create table if not exists ${members} (
  ${memberTeam} ${idType} not null references ${teams} (${id}) on delete cascade,
  ${memberUser} uuid not null references auth.users (id) on delete cascade,
  ${memberTenant} ${ctx.idType} not null,
  ${memberCreated} timestamptz not null default now(),
  primary key (${memberTeam}, ${memberUser})
);`
}
create index if not exists ${ctx.naming.rename("team_members_user_idx")} on ${members} (${memberUser});
create index if not exists ${ctx.naming.rename("team_members_membership_idx")} on ${members} (${memberTenant}, ${memberUser});
${lockTable(members, { read: true })}
${renderPolicy(makePolicy({ table: members, name: ctx.naming.rename("team_members_read"), command: "select", roles: ["authenticated"], using: `${memberTenant} in (select ${ctx.scope.ids(read)})` }), { target: members })}
${membershipFk(ctx, members, memberTenant, memberUser)}
`
    : "";

  const fn = (value: string): string => ctx.fn(value);
  const provided = providerTeamIds(ctx, layout, "team_ids_of.member");

  const teamIdsBody =
    provided === undefined
      ? `select ${memberTeam} from ${members} where ${memberUser} = team_ids_of.member`
      : `select t.id::${idType} from ${provided} as t(id)`;

  return `${schemaPreamble(ctx)}
-- Teams belong to a tenant. Inbox assignment uses these rows when inbox is installed.
${tables}
${inboxTeamKey(ctx, teams, id)}
-- A signed-in caller may only read their own teams; the service role and
-- direct database sessions (no request role) may read anyone's.
create or replace function ${fn("team_ids_of")}(member uuid)
returns setof ${idType}
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if team_ids_of.member is distinct from (select auth.uid())
    and coalesce((select auth.jwt() ->> 'role'), 'service_role') <> 'service_role' then
    ${fail("TEAM_FORBIDDEN", "team_ids_of reads only the caller's teams")}
  end if;
  return query ${teamIdsBody};
end;
$$;
${userGrant(`${fn("team_ids_of")}(uuid)`)}

-- fields: the extra columns (columns your schema files add) to set.
${
  patching
    ? drops(fn("create_team"), `${ctx.idType}, text, text`, [
        "",
        ", jsonb",
        extras.length === 0 ? ", text, jsonb" : ", text",
      ])
    : `${extra.drop(fn("create_team"), `${ctx.idType}, text, text`)}
${drops(fn("create_team"), `${ctx.idType}, text, text`, [", text", ", text, jsonb"])}`
}
create or replace function ${fn("create_team")}(tenant ${ctx.idType}, name text, description text${patching ? ", slug text default null" : ""}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id ${idType};
  v_slug text := ${patching ? `coalesce(create_team.slug, ${derivedSlug})` : derivedSlug};
begin
  if not (${service(ctx)} or ${ctx.scope.can("create_team.tenant", create)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  if v_slug is null or v_slug = ''${patching ? ` or (create_team.slug is not null and create_team.slug !~ ${SLUG})` : ""} then
    ${fail("TEAM_SLUG_INVALID", "team name needs a slug", "22023")}
  end if;
  ${ctx.hook("before_team_create", [
    [ctx.idType, "create_team.tenant"],
    ["text", "v_slug"],
  ])}
  insert into ${teams} (${tenant}, ${name}, ${slug}, ${description}, ${createdBy}${required.columns})
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid()${required.values})
  returning ${id} into v_id;${writeExtraColumns(teams, extras, "create_team.fields", `x.${id} = v_id`)}
  ${record(ctx, "team.created", "v_id", "create_team.tenant", "create_team.name")}
  ${ctx.hook("after_team_create", [
    [idType, "v_id"],
    [ctx.idType, "create_team.tenant"],
  ])}
  return ${extras.length === 0 ? "jsonb_build_object('id', v_id, 'slug', v_slug)" : `(select ${teamJson("x")} from ${teams} x where x.${id} = v_id)`};
end;
$$;
${userGrant(`${fn("create_team")}(${ctx.idType}, text, text${patching ? ", text" : ""}${extra.type})`)}

${
  patching
    ? `${drops(fn("update_team"), `${idType}, text, text`, [
        "",
        ", jsonb",
        ...(extras.length === 0 ? [", jsonb, jsonb"] : []),
      ])}
-- patch: name, slug and description to set; a key that is present sets its
-- column, so null clears the description.`
    : extra.drop(fn("update_team"), `${idType}, text, text`)
}
create or replace function ${fn("update_team")}(team ${idType}, name text, description text${patching ? ", patch jsonb default null" : ""}${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = update_team.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", update)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
${
  patching
    ? `  if update_team.patch is not null and (jsonb_typeof(update_team.patch) <> 'object'
    or update_team.patch ? 'slug' and coalesce(update_team.patch ->> 'slug', '') !~ ${SLUG}
    or update_team.patch ? 'name' and nullif(trim(update_team.patch ->> 'name'), '') is null) then
    ${fail("TEAM_INVALID", "patch sets name, slug or description; name and slug can't be empty", "22023")}
  end if;
  update ${teams} as t
  set ${name} = coalesce(update_team.patch ->> 'name', update_team.name, t.${name}),
      ${slug} = case when update_team.patch ? 'slug' then update_team.patch ->> 'slug' else t.${slug} end,
      ${description} = case when update_team.patch ? 'description' then update_team.patch ->> 'description' else coalesce(update_team.description, t.${description}) end,
      ${updatedAt} = now()`
    : `  update ${teams} as t
  set ${name} = coalesce(update_team.name, t.${name}),
      ${description} = coalesce(update_team.description, t.${description}),
      ${updatedAt} = now()`
}
  where t.${id} = update_team.team;${writeExtraColumns(teams, extras, "update_team.fields", `x.${id} = update_team.team`)}
  ${record(ctx, "team.updated", "update_team.team", "v_tenant", "update_team.name")}
  return (select ${teamJson("x")} from ${teams} x where x.${id} = update_team.team);
end;
$$;
${userGrant(`${fn("update_team")}(${idType}, text, text${patching ? ", jsonb" : ""}${extra.type})`)}

create or replace function ${fn("archive_team")}(team ${idType})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = archive_team.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", update)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  update ${teams} set ${status} = 'archived', ${updatedAt} = now() where ${id} = archive_team.team;
  ${record(ctx, "team.archived", "archive_team.team", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("archive_team")}(${idType})`)}
${
  restoring
    ? `
create or replace function ${fn("restore_team")}(team ${idType})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = restore_team.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", update)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  update ${teams} set ${status} = 'active', ${updatedAt} = now() where ${id} = restore_team.team;
  ${record(ctx, "team.restored", "restore_team.team", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("restore_team")}(${idType})`)}
`
    : ""
}
create or replace function ${fn("delete_team")}(team ${idType})
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = delete_team.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", remove)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  delete from ${teams} where ${id} = delete_team.team;
  ${record(ctx, "team.deleted", "delete_team.team", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("delete_team")}(${idType})`)}

${
  employees
    ? employeeMemberFunctions(ctx, idType, membersKey)
    : `create or replace function ${fn("add_team_member")}(team ${idType}, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = add_team_member.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", membersKey)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  ${membershipCheck(ctx, "v_tenant", "add_team_member.member")}
  insert into ${members} (${memberTeam}, ${memberUser}, ${memberTenant})
  values (add_team_member.team, add_team_member.member, v_tenant)
  on conflict do nothing;
  ${record(ctx, "team_member.added", "add_team_member.team", "v_tenant", undefined, "add_team_member.member")}
  return true;
end;
$$;
${userGrant(`${fn("add_team_member")}(${idType}, uuid)`)}

create or replace function ${fn("remove_team_member")}(team ${idType}, member uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
begin
  select ${tenant} into v_tenant from ${teams} where ${id} = remove_team_member.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", membersKey)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  delete from ${members}
  where ${memberTeam} = remove_team_member.team and ${memberUser} = remove_team_member.member;
  ${record(ctx, "team_member.deleted", "remove_team_member.team", "v_tenant", undefined, "remove_team_member.member")}
  return found;
end;
$$;
${userGrant(`${fn("remove_team_member")}(${idType}, uuid)`)}

`
}create or replace function ${fn("list_teams")}(tenant ${ctx.idType})
returns jsonb
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'id', t.${id},
    'name', t.${name},
    'slug', t.${slug},
    'description', t.${description},
    'status', t.${status},
    'member_ids', coalesce((
      select jsonb_agg(m.${memberUser} order by m.${memberCreated})${employees ? ` filter (where m.${memberUser} is not null)` : ""}
      from ${members} m
      where m.${memberTeam} = t.${id}
    ), '[]'::jsonb)${
      employees
        ? `,
    'member_employee_ids', coalesce((
      select jsonb_agg(m.${ctx.col("members", "employee")} order by m.${memberCreated}) filter (where m.${ctx.col("members", "employee")} is not null)
      from ${members} m
      where m.${memberTeam} = t.${id}
    ), '[]'::jsonb)`
        : ""
    }${extraFieldsJson("t", extras)}
  ) order by t.${name}), '[]'::jsonb)
  from ${teams} t
  where t.${tenant} = list_teams.tenant
    and (
      ${service(ctx)}
      or ${ctx.scope.can("list_teams.tenant", read)}
    )
$$;
${userGrant(`${fn("list_teams")}(${ctx.idType})`)}
`;
}

/**
 * Whether `team_members` holds employees next to users: the employees block is
 * installed and `columns.members.employee` isn't mapped to `null`.
 */
export function employeeMembers(ctx: BlockSqlContext): boolean {
  return (
    ctx.mode !== "custom" &&
    ctx.installed("employees") &&
    ctx.of("employees").mode !== "custom" &&
    ctx.has("members", "employee")
  );
}

/** Whether `user` of `tenant` is a member, or `true` without memberships. */
export function isTenantMember(
  ctx: BlockSqlContext,
  tenant: string,
  user: string,
): string {
  if (!ctx.installed("memberships")) {
    return "true";
  }

  const memberships = ctx.of("memberships");

  return `exists (
    select 1 from ${memberships.table("memberships")} m
    where m.${memberships.col("memberships", "tenant")} = ${tenant}
      and m.${memberships.col("memberships", "user")} = ${user}
  )`;
}

function employeeMembersTable(
  ctx: BlockSqlContext,
  idType: "uuid" | "bigint",
): string {
  const members = ctx.table("members");
  const name = ctx.tableName("members").name;
  const m = (column: string): string => ctx.col("members", column);

  const repair =
    ctx.rerunnable && ctx.owns("members")
      ? `
alter table ${members} add column if not exists ${m("employee")} uuid;
alter table ${members} drop constraint if exists ${sqlIdent(`${name}_pkey`)};
alter table ${members} alter column ${m("user")} drop not null;`
      : "";

  return `create table if not exists ${members} (
  ${m("team")} ${idType} not null references ${ctx.table("teams")} (${ctx.col("teams", "id")}) on delete cascade,
  ${m("user")} uuid references auth.users (id) on delete cascade,
  ${m("employee")} uuid,
  ${m("tenant")} ${ctx.idType} not null,
  ${m("createdAt")} timestamptz not null default now(),
  check (${m("user")} is not null or ${m("employee")} is not null)
);${repair}
create unique index if not exists ${sqlIdent(`bsb_${name}_user_key`)} on ${members} (${m("team")}, ${m("user")}) where ${m("user")} is not null;
create unique index if not exists ${sqlIdent(`bsb_${name}_employee_key`)} on ${members} (${m("team")}, ${m("employee")}) where ${m("employee")} is not null;
create index if not exists ${ctx.naming.rename("team_members_employee_idx")} on ${members} (${m("employee")}) where ${m("employee")} is not null;`;
}

/**
 * `add_team_member` and `remove_team_member` that take a user or an employee,
 * and the trigger that keeps an employee's row when its user goes.
 */
function employeeMemberFunctions(
  ctx: BlockSqlContext,
  idType: "uuid" | "bigint",
  membersKey: string,
): string {
  const fn = (value: string): string => ctx.fn(value);
  const teams = ctx.table("teams");
  const members = ctx.table("members");
  const id = ctx.col("teams", "id");
  const tenant = ctx.col("teams", "tenant");
  const m = (column: string): string => ctx.col("members", column);
  const people = ctx.of("employees");
  const employees = people.table("employees");
  const e = (column: string): string => people.col("employees", column);
  const keep = ctx.naming.rename("bsb_team_member_employee_keep");

  const guard = (
    call: string,
  ): string => `select ${tenant} into v_tenant from ${teams} where ${id} = ${call}.team;
  if not found then
    ${fail("TEAM_NOT_FOUND", "team not found", "P0002")}
  end if;
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", membersKey)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  if (${call}.member is null) = (${call}.employee is null) then
    ${fail("TEAM_MEMBER_INVALID", "pass either a user or an employee", "22023")}
  end if;`;

  return `-- A row whose employee stays (the team and the employee exist) keeps the
-- employee when its user loses the account or the tenant membership.
create or replace function better_supabase.${keep}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.${m("employee")} is null or old.${m("user")} is null
    or not exists (select 1 from ${teams} t where t.${id} = old.${m("team")})
    or not exists (select 1 from ${employees} x where x.${e("id")} = old.${m("employee")})
    or (exists (select 1 from auth.users u where u.id = old.${m("user")})
      and ${isTenantMember(ctx, `old.${m("tenant")}`, `old.${m("user")}`)}) then
    return old;
  end if;
  update ${members} set ${m("user")} = null
  where ${m("team")} = old.${m("team")} and ${m("employee")} = old.${m("employee")};
  return null;
end;
$$;
${triggerGrant(`better_supabase.${keep}()`)}
drop trigger if exists ${keep} on ${members};
create trigger ${keep} before delete on ${members}
for each row execute function better_supabase.${keep}();

drop function if exists ${fn("add_team_member")}(${idType}, uuid);
-- member: a user id; employee: an employee id. Pass one of them.
create or replace function ${fn("add_team_member")}(team ${idType}, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_user uuid := add_team_member.member;
  v_employee uuid := add_team_member.employee;
begin
  ${guard("add_team_member")}
  if v_employee is null then
    ${membershipCheck(ctx, "v_tenant", "v_user")}
    v_employee := (
      select x.${e("id")} from ${employees} x
      where x.${e("tenant")} = v_tenant and x.${e("user")} = v_user
    );
  else
    select x.${e("user")} into v_user from ${employees} x
    where x.${e("id")} = v_employee and x.${e("tenant")} = v_tenant;
    if not found then
      ${fail("TEAM_MEMBER_INVALID", "employee is not in the tenant", "22023")}
    end if;
    if v_user is not null and not ${isTenantMember(ctx, "v_tenant", "v_user")} then
      v_user := null;
    end if;
  end if;
  if v_employee is not null and v_user is not null then
    delete from ${members} x
    where x.${m("team")} = add_team_member.team and x.${m("user")} = v_user and x.${m("employee")} is null
      and exists (
        select 1 from ${members} y
        where y.${m("team")} = add_team_member.team and y.${m("employee")} = v_employee
      );
    update ${members} set ${m("user")} = v_user
    where ${m("team")} = add_team_member.team and ${m("employee")} = v_employee and ${m("user")} is null;
    update ${members} set ${m("employee")} = v_employee
    where ${m("team")} = add_team_member.team and ${m("user")} = v_user and ${m("employee")} is null;
  end if;
  insert into ${members} (${m("team")}, ${m("user")}, ${m("employee")}, ${m("tenant")})
  values (add_team_member.team, v_user, v_employee, v_tenant)
  on conflict do nothing;
  ${record(ctx, "team_member.added", "add_team_member.team", "v_tenant", undefined, "v_user", "v_employee")}
  return true;
end;
$$;
${userGrant(`${fn("add_team_member")}(${idType}, uuid, uuid)`)}

drop function if exists ${fn("remove_team_member")}(${idType}, uuid);
-- member: a user id; employee: an employee id. Pass one of them. Removing a
-- user whose row has an employee removes the employee too.
create or replace function ${fn("remove_team_member")}(team ${idType}, member uuid default null, employee uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${ctx.idType};
  v_user uuid;
  v_employee uuid;
begin
  ${guard("remove_team_member")}
  delete from ${members} x
  where x.${m("team")} = remove_team_member.team
    and (x.${m("employee")} = remove_team_member.employee or x.${m("user")} = remove_team_member.member)
  returning x.${m("user")}, x.${m("employee")} into v_user, v_employee;
  if not found then
    return false;
  end if;
  ${record(ctx, "team_member.deleted", "remove_team_member.team", "v_tenant", undefined, "v_user", "v_employee")}
  return true;
end;
$$;
${userGrant(`${fn("remove_team_member")}(${idType}, uuid, uuid)`)}

`;
}

/**
 * Existing rows of an app that installs employees next to teams: members get
 * the employee behind their account, and each employee with a team is on it.
 */
function employeeMembersData(ctx: BlockSqlContext): string {
  if (!employeeMembers(ctx)) {
    return "";
  }

  const members = ctx.table("members");
  const m = (column: string): string => ctx.col("members", column);
  const people = ctx.of("employees");
  const employees = people.table("employees");
  const e = (column: string): string => people.col("employees", column);

  const primary =
    people.has("employees", "team") && teamIdType(ctx) === "uuid"
      ? `
insert into ${members} (${m("team")}, ${m("user")}, ${m("employee")}, ${m("tenant")})
select t.${ctx.col("teams", "id")},
  case when ${isTenantMember(ctx, `x.${e("tenant")}`, `x.${e("user")}`)} then x.${e("user")} end,
  x.${e("id")}, x.${e("tenant")}
from ${employees} x
join ${ctx.table("teams")} t on t.${ctx.col("teams", "id")} = x.${e("team")} and t.${ctx.col("teams", "tenant")} = x.${e("tenant")}
on conflict do nothing;`
      : "";

  return `-- Members with an employee record get its id.
update ${members} y set ${m("employee")} = x.${e("id")}
from ${employees} x
where y.${m("employee")} is null and x.${e("tenant")} = y.${m("tenant")} and x.${e("user")} = y.${m("user")}
  and not exists (
    select 1 from ${members} z
    where z.${m("team")} = y.${m("team")} and z.${m("employee")} = x.${e("id")}
  );${primary}`;
}

function service(ctx: BlockSqlContext): string {
  return ctx.installed("permissions")
    ? "auth.role() = 'service_role'"
    : "false";
}

function membershipFk(
  ctx: BlockSqlContext,
  members: string,
  tenant: string,
  user: string,
): string {
  if (!ctx.installed("memberships")) {
    return "";
  }

  const memberships = ctx.of("memberships");

  return `alter table ${members} drop constraint if exists ${ctx.naming.rename("team_members_membership_fkey")};
alter table ${members}
  add constraint ${ctx.naming.rename("team_members_membership_fkey")}
  foreign key (${tenant}, ${user})
  references ${memberships.table("memberships")} (${memberships.col("memberships", "tenant")}, ${memberships.col("memberships", "user")})
  on delete cascade;`;
}

function membershipCheck(
  ctx: BlockSqlContext,
  tenant: string,
  user: string,
): string {
  if (!ctx.installed("memberships")) {
    return "";
  }

  const memberships = ctx.of("memberships");

  return `if not exists (
    select 1 from ${memberships.table("memberships")} m
    where m.${memberships.col("memberships", "tenant")} = ${tenant}
      and m.${memberships.col("memberships", "user")} = ${user}
  ) then
    ${fail("TEAM_MEMBER_INVALID", "user is not a member of the tenant", "22023")}
  end if;`;
}

/** Inbox conversations point at the shared teams table. */
function inboxTeamKey(ctx: BlockSqlContext, teams: string, id: string): string {
  if (!ctx.installed("inbox") || !ctx.owns("teams")) {
    return "";
  }

  const inbox = ctx.of("inbox");

  return `alter table ${inbox.table("conversations")}
  add constraint conversations_team_fkey
  foreign key (${inbox.col("conversations", "team")}) references ${teams} (${id}) on delete set null;`;
}

/**
 * Moves the inbox's own team rows into the shared tables and drops the old
 * tables. Rows only an installed database holds, so it runs as an upgrade step
 * before the module file adds the new foreign key.
 */
function inboxMove(ctx: BlockSqlContext): string {
  if (!ctx.installed("inbox") || !ctx.owns("teams")) {
    return "";
  }

  const inbox = ctx.of("inbox");
  const teams = ctx.table("teams");
  const members = ctx.table("members");
  const id = ctx.col("teams", "id");
  const tenant = ctx.col("teams", "tenant");
  const name = ctx.col("teams", "name");
  const slug = ctx.col("teams", "slug");
  const oldTeams = inbox.table("teams");
  const oldMembers = inbox.table("teamMembers");
  const conversations = inbox.table("conversations");
  const oldId = inbox.col("teams", "id");
  const oldTenant = inbox.col("teams", "tenant");
  const oldName = inbox.col("teams", "name");
  const oldTeam = inbox.col("teamMembers", "team");
  const oldUser = inbox.col("teamMembers", "user");
  const memberTeam = ctx.col("members", "team");
  const memberUser = ctx.col("members", "user");
  const memberTenant = ctx.col("members", "tenant");

  return `do $shared_teams$
declare
  legacy record;
begin
  if to_regclass(${sqlString(oldTeams.replaceAll('"', ""))}) is null then
    return;
  end if;
  insert into ${teams} (${id}, ${tenant}, ${name}, ${slug})
  select ${oldId}, ${oldTenant}, ${oldName},
    trim(both '-' from regexp_replace(lower(${oldName}), '[^a-z0-9]+', '-', 'g'))
  from ${oldTeams}
  on conflict do nothing;
  insert into ${members} (${memberTeam}, ${memberUser}, ${memberTenant})
  select m.${oldTeam}, m.${oldUser}, t.${oldTenant}
  from ${oldMembers} m
  join ${oldTeams} t on t.${oldId} = m.${oldTeam}
  on conflict do nothing;
  for legacy in
    select con.conname as name, con.conrelid::regclass as rel
    from pg_catalog.pg_constraint con
    where con.confrelid = ${sqlString(oldTeams.replaceAll('"', ""))}::regclass
  loop
    execute format('alter table %s drop constraint %I', legacy.rel, legacy.name);
  end loop;
  drop table ${oldMembers};
  drop table ${oldTeams};
end
$shared_teams$;
alter table ${conversations}
  drop constraint if exists conversations_team_fkey;`;
}

function record(
  ctx: BlockSqlContext,
  type: keyof typeof EVENTS,
  id: string,
  tenant: string,
  name?: string,
  userId?: string,
  employeeId?: string,
): string {
  const payload = [
    `'organizationId', ${tenant}`,
    `'id', ${id}`,
    ...(name ? [`'name', ${name}`] : []),
    ...(userId ? [`'userId', ${userId}`] : []),
    ...(employeeId ? [`'employeeId', ${employeeId}`] : []),
  ].join(", ");

  return ctx.record({
    type,
    payload: `jsonb_build_object(${payload})`,
    subject: `'teams/' || (${id})::text`,
    tenant,
    audit: {
      category: "membership",
      targetType: "team",
      recordId: `(${id})::text`,
    },
  });
}

function contract(ctx: BlockSqlContext): readonly BlockSqlContractFunction[] {
  const id = teamIdType(ctx);
  const extra = extraFieldsArg(ctx.extraColumns("teams", RESERVED)).contract;

  return [
    {
      name: "create_team",
      args: [
        "{id}",
        "text",
        "text",
        ...(ctx.flag("patch", false) ? ["text"] : []),
        ...extra,
      ],
      returns: "jsonb",
    },
    {
      name: "update_team",
      args: [
        id,
        "text",
        "text",
        ...(ctx.flag("patch", false) ? ["jsonb"] : []),
        ...extra,
      ],
      returns: "jsonb",
    },
    { name: "archive_team", args: [id], returns: "boolean" },
    ...(ctx.flag("restore", false)
      ? [{ name: "restore_team", args: [id], returns: "boolean" }]
      : []),
    { name: "delete_team", args: [id], returns: "boolean" },
    ...(["add_team_member", "remove_team_member"] as const).map((name) => ({
      name,
      args: employeeMembers(ctx) ? [id, "uuid", "uuid"] : [id, "uuid"],
      returns: "boolean",
    })),
    { name: "list_teams", args: ["{id}"], returns: "jsonb" },
    { name: "team_ids_of", args: ["uuid"], returns: `setof ${id}` },
  ];
}

export const TEAMS: BlockSqlDefinition = {
  name: "teams",
  scopes: ["tenant"],
  title: "Teams",
  description:
    "Tenant teams and their members. Inbox assignment uses these rows instead of its own team tables.",
  requires: ["memberships", "permissions"],
  integrates: ["inbox", "outbox", "audit", "employees"],
  target: "schema",
  modes: ["managed", "custom"],
  version: 3,
  upgrades: [
    {
      from: 1,
      description:
        "team_ids_of(member) refuses a signed-in caller that names another user; the service role and direct database sessions still read anyone's teams.",
      sql: () => "",
    },
    {
      from: 2,
      description:
        "The inbox's own team tables move into teams and team_members, and inbox conversations point at teams.",
      sql: inboxMove,
    },
  ],
  names: NAMES,
  contract,
  build,
  data: employeeMembersData,
};
