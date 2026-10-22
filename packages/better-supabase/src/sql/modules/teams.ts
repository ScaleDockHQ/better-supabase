import type { TeamsEvents } from "../../blocks/teams/events.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlEvents,
  BlockSqlNames,
} from "../context.ts";
import type { BlockSqlDefinition, BlockSqlLayout } from "../module-types.ts";

import { sqlString } from "../../core/template.ts";
import {
  addExtraColumns,
  extraFieldsArg,
  extraFieldsJson,
  fail,
  lockTable,
  schemaPreamble,
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
  "team.deleted": { subject: "teams", payload: ["organizationId", "id"] },
  "team_member.added": {
    subject: "teams",
    payload: ["organizationId", "id", "userId"],
  },
  "team_member.removed": {
    subject: "teams",
    payload: ["organizationId", "id", "userId"],
  },
};

const NAMES: BlockSqlNames = {
  entities: { team: { table: "teams", singular: "team", primary: true } },
  events: EVENTS,
  hooks: ["before_team_create", "after_team_create"],
  options: ["teamIdType", "extraColumns"],
  tables: {
    teams: {
      name: "teams",
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
      lifecycle: { tenant: "tenant", user: "user", export: true },
      columns: {
        team: "team_id",
        user: "user_id",
        tenant: "tenant_id",
        createdAt: "created_at",
      },
    },
  },
};

/** The keys the team reads return next to the extra columns. */
const RESERVED = ["fields"] as const;

function teamIdType(ctx: BlockSqlContext): "uuid" | "bigint" {
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
  const manage = ctx.permission("manage", OPERATIONS["teams.manage"]);
  const read = ctx.permission("read", OPERATIONS["teams.read"]);
  const extras = ctx.extraColumns("teams", RESERVED);
  const extra = extraFieldsArg(extras);

  const teamJson = (alias: string): string =>
    `jsonb_build_object('id', ${alias}.${id}, 'slug', ${alias}.${slug}${extraFieldsJson(alias, extras)})`;

  const idDefault =
    idType === "uuid"
      ? " default gen_random_uuid()"
      : " generated always as identity";

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
);${addExtraColumns(teams, extras)}
${lockTable(teams, { read: true })}
drop policy if exists ${ctx.naming.rename("teams_read")} on ${teams};
create policy ${ctx.naming.rename("teams_read")} on ${teams} for select to authenticated
using (${tenant} in (select ${ctx.scope.ids(read)}));

create table if not exists ${members} (
  ${memberTeam} ${idType} not null references ${teams} (${id}) on delete cascade,
  ${memberUser} uuid not null references auth.users (id) on delete cascade,
  ${memberTenant} ${ctx.idType} not null,
  ${memberCreated} timestamptz not null default now(),
  primary key (${memberTeam}, ${memberUser})
);
create index if not exists ${ctx.naming.rename("team_members_user_idx")} on ${members} (${memberUser});
create index if not exists ${ctx.naming.rename("team_members_membership_idx")} on ${members} (${memberTenant}, ${memberUser});
${lockTable(members, { read: true })}
drop policy if exists ${ctx.naming.rename("team_members_read")} on ${members};
create policy ${ctx.naming.rename("team_members_read")} on ${members} for select to authenticated
using (${memberTenant} in (select ${ctx.scope.ids(read)}));
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
${inboxMove(ctx, teams, members, id, tenant, name, slug)}
create or replace function ${fn("team_ids_of")}(member uuid)
returns setof ${idType}
language sql
stable
security definer
set search_path = ''
as $$
  ${teamIdsBody}
$$;
${userGrant(`${fn("team_ids_of")}(uuid)`)}

-- fields: the extra columns (blocks.teams.options.extraColumns) to set.
${extra.drop(fn("create_team"), `${ctx.idType}, text, text`)}
create or replace function ${fn("create_team")}(tenant ${ctx.idType}, name text, description text${extra.param})
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id ${idType};
  v_slug text := trim(both '-' from regexp_replace(lower(create_team.name), '[^a-z0-9]+', '-', 'g'));
begin
  if not (${service(ctx)} or ${ctx.scope.can("create_team.tenant", manage)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  if v_slug is null or v_slug = '' then
    ${fail("TEAM_SLUG_INVALID", "team name needs a slug", "22023")}
  end if;
  ${ctx.hook("before_team_create", [
    [ctx.idType, "create_team.tenant"],
    ["text", "v_slug"],
  ])}
  insert into ${teams} (${tenant}, ${name}, ${slug}, ${description}, ${createdBy})
  values (create_team.tenant, create_team.name, v_slug, create_team.description, auth.uid())
  returning ${id} into v_id;${writeExtraColumns(teams, extras, "create_team.fields", `x.${id} = v_id`)}
  ${record(ctx, "team.created", "v_id", "create_team.tenant", "create_team.name")}
  ${ctx.hook("after_team_create", [
    [idType, "v_id"],
    [ctx.idType, "create_team.tenant"],
  ])}
  return ${extras.length === 0 ? "jsonb_build_object('id', v_id, 'slug', v_slug)" : `(select ${teamJson("x")} from ${teams} x where x.${id} = v_id)`};
end;
$$;
${userGrant(`${fn("create_team")}(${ctx.idType}, text, text${extra.type})`)}

${extra.drop(fn("update_team"), `${idType}, text, text`)}
create or replace function ${fn("update_team")}(team ${idType}, name text, description text${extra.param})
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
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  update ${teams} as t
  set ${name} = coalesce(update_team.name, t.${name}),
      ${description} = coalesce(update_team.description, t.${description}),
      ${updatedAt} = now()
  where t.${id} = update_team.team;${writeExtraColumns(teams, extras, "update_team.fields", `x.${id} = update_team.team`)}
  ${record(ctx, "team.updated", "update_team.team", "v_tenant", "update_team.name")}
  return ${extras.length === 0 ? "jsonb_build_object('id', update_team.team)" : `(select ${teamJson("x")} from ${teams} x where x.${id} = update_team.team)`};
end;
$$;
${userGrant(`${fn("update_team")}(${idType}, text, text${extra.type})`)}

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
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  update ${teams} set ${status} = 'archived', ${updatedAt} = now() where ${id} = archive_team.team;
  ${record(ctx, "team.archived", "archive_team.team", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("archive_team")}(${idType})`)}

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
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  delete from ${teams} where ${id} = delete_team.team;
  ${record(ctx, "team.deleted", "delete_team.team", "v_tenant")}
  return true;
end;
$$;
${userGrant(`${fn("delete_team")}(${idType})`)}

create or replace function ${fn("add_team_member")}(team ${idType}, member uuid)
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
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", manage)}) then
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
  if not (${service(ctx)} or ${ctx.scope.can("v_tenant", manage)}) then
    ${fail("TEAM_FORBIDDEN", "not allowed to manage teams")}
  end if;
  delete from ${members}
  where ${memberTeam} = remove_team_member.team and ${memberUser} = remove_team_member.member;
  ${record(ctx, "team_member.removed", "remove_team_member.team", "v_tenant", undefined, "remove_team_member.member")}
  return found;
end;
$$;
${userGrant(`${fn("remove_team_member")}(${idType}, uuid)`)}

create or replace function ${fn("list_teams")}(tenant ${ctx.idType})
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
    'status', t.${status}${extraFieldsJson("t", extras)}
  )), '[]'::jsonb)
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
  references ${memberships.table("memberships")} (${memberships.col("memberships", "tenant")}, ${memberships.col("memberships", "user")});`;
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

function inboxMove(
  ctx: BlockSqlContext,
  teams: string,
  members: string,
  id: string,
  tenant: string,
  name: string,
  slug: string,
): string {
  if (!ctx.installed("inbox") || !ctx.manages) {
    return "";
  }

  const inbox = ctx.of("inbox");
  const oldTeams = inbox.table("teams");
  const oldMembers = inbox.table("teamMembers");
  const conversations = inbox.table("conversations");
  const oldId = inbox.col("teams", "id");
  const oldTenant = inbox.col("teams", "tenant");
  const oldName = inbox.col("teams", "name");
  const oldTeam = inbox.col("teamMembers", "team");
  const oldUser = inbox.col("teamMembers", "user");
  const conversationTeam = inbox.col("conversations", "team");
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
  drop constraint if exists conversations_team_fkey;
alter table ${conversations}
  add constraint conversations_team_fkey
  foreign key (${conversationTeam}) references ${teams} (${id}) on delete set null;`;
}

function record(
  ctx: BlockSqlContext,
  type: keyof typeof EVENTS,
  id: string,
  tenant: string,
  name?: string,
  userId?: string,
): string {
  const payload = [
    `'organizationId', ${tenant}`,
    `'id', ${id}`,
    ...(name ? [`'name', ${name}`] : []),
    ...(userId ? [`'userId', ${userId}`] : []),
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
      args: ["{id}", "text", "text", ...extra],
      returns: "jsonb",
    },
    {
      name: "update_team",
      args: [id, "text", "text", ...extra],
      returns: "jsonb",
    },
    { name: "archive_team", args: [id], returns: "boolean" },
    { name: "delete_team", args: [id], returns: "boolean" },
    { name: "add_team_member", args: [id, "uuid"], returns: "boolean" },
    { name: "remove_team_member", args: [id, "uuid"], returns: "boolean" },
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
  integrates: ["inbox", "outbox", "audit"],
  target: "schema",
  modes: ["managed", "adopt", "custom"],
  version: 1,
  names: NAMES,
  contract,
  build,
};
