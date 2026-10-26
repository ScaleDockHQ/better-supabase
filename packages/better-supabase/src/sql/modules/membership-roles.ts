import type { BlockSqlContext } from "../context.ts";

import { isRecord } from "../../core/guards.ts";
import { sqlString } from "../../core/template.ts";
import { policy as makePolicy, renderPolicy } from "../policy.ts";
import { accessModel, roleNames } from "./permissions-model.ts";

const WHERE = "blocks.memberships.options.roles";

/** Set while the set's trigger writes the primary role, so it isn't read back. */
const SYNC = "'better_supabase.membership_role_sync'";

/**
 * Whether `blocks.memberships.options.roles.many` is on: each membership holds
 * a set of role names in `membership_roles`, and `memberships.role` keeps the
 * highest-ranked of them. `tenant` is the memberships module's context.
 */
export function manyRoles(tenant: BlockSqlContext): boolean {
  const value = tenant.option("roles");

  if (value === undefined) {
    return false;
  }

  if (
    !isRecord(value) ||
    Object.keys(value).some((key) => key !== "many") ||
    (value["many"] !== undefined && typeof value["many"] !== "boolean")
  ) {
    throw new TypeError(`${WHERE} must be { many: boolean }`);
  }

  if (value["many"] !== true) {
    return false;
  }

  if (
    accessModel(tenant) === "catalog" ||
    tenant.option("roleThrough") !== undefined
  ) {
    throw new TypeError(
      `${WHERE}.many stores role names in membership_roles; the catalog model and roleThrough store role ids, so use the roles model or an authorization provider`,
    );
  }

  if (!tenant.manages) {
    throw new TypeError(
      `${WHERE}.many keys membership_roles on the block's memberships table; it can't run over an app's own memberships table`,
    );
  }

  return true;
}

/** The quoted `membership_roles` table, in the memberships module's schema. */
export const membershipRolesTable = (tenant: BlockSqlContext): string =>
  `${tenant.schema}."membership_roles"`;

/**
 * Whether membership row `alias` holds a role in `roles` (a `text[]`
 * expression): the role column with one role, the set with many.
 */
export function holdsRole(
  tenant: BlockSqlContext,
  alias: string,
  roles: string,
  roleName: string,
): string {
  if (!manyRoles(tenant)) {
    return `${roleName} = any (${roles})`;
  }

  const t = tenant.col("memberships", "tenant");
  const u = tenant.col("memberships", "user");

  return `exists (select 1 from ${membershipRolesTable(tenant)} mr where mr.${t} = ${alias}.${t} and mr.${u} = ${alias}.${u} and mr."role" = any (${roles}))`;
}

/** Postgres array of the declared roles, highest-ranked first. */
const rankArray = (tenant: BlockSqlContext): string =>
  `array[${roleNames(tenant).map(sqlString).join(", ")}]::text[]`;

/**
 * The `membership_roles` table and the triggers that keep it and
 * `memberships.role` in step, or the statements that remove the triggers when
 * `many` is off. The table and its rows stay when `many` is turned off.
 */
export function membershipRolesSql(tenant: BlockSqlContext): string {
  const m = tenant.table("memberships");
  const mr = membershipRolesTable(tenant);
  const t = tenant.col("memberships", "tenant");
  const u = tenant.col("memberships", "user");
  const role = tenant.col("memberships", "role");
  const fromRole = tenant.fn("membership_roles_from_role");
  const toRole = tenant.fn("membership_role_from_roles");

  if (!manyRoles(tenant)) {
    return `
drop trigger if exists ${tenant.trigger("membership_roles")} on ${m};
drop function if exists ${fromRole}() cascade;
drop function if exists ${toRole}() cascade;
`;
  }

  const ranks = rankArray(tenant);

  return `
-- blocks.memberships.options.roles.many: every membership holds a set of
-- roles. ${m}.${role} keeps the highest-ranked one (the order of
-- blocks.permissions.roles), so readers of the single role keep working.
create table if not exists ${mr} (
  ${t} ${tenant.idType} not null,
  ${u} uuid not null,
  "role" text not null,
  "created_at" timestamptz not null default now(),
  primary key (${t}, ${u}, "role"),
  foreign key (${t}, ${u}) references ${m} (${t}, ${u}) on delete cascade
);
create index if not exists membership_roles_user_idx on ${mr} (${u});
alter table ${mr} drop constraint if exists membership_roles_role_check;
alter table ${mr}
  add constraint membership_roles_role_check check ("role" in (${roleNames(tenant).map(sqlString).join(", ")}));
alter table ${mr} enable row level security;
grant select on ${mr} to authenticated;
grant all on ${mr} to service_role;

insert into ${mr} (${t}, ${u}, "role")
select m.${t}, m.${u}, m.${role}::text from ${m} m
where m.${role} is not null
on conflict do nothing;

-- Writing ${role} directly (update_member_role, a client policy, the service
-- role) replaces the set with that one role.
create or replace function ${fromRole}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${role} is null or current_setting(${SYNC}, true) = 'on' then
    return null;
  end if;
  delete from ${mr} r where r.${t} = new.${t} and r.${u} = new.${u} and r."role" <> new.${role}::text;
  insert into ${mr} (${t}, ${u}, "role") values (new.${t}, new.${u}, new.${role}::text)
  on conflict do nothing;
  return null;
end;
$$;
revoke execute on function ${fromRole}() from public, anon, authenticated;
drop trigger if exists ${tenant.trigger("membership_roles")} on ${m};
create trigger ${tenant.trigger("membership_roles")} after insert or update of ${role} on ${m}
  for each row execute function ${fromRole}();

-- Adding or removing a role moves ${role} to the highest-ranked one left. An
-- emptied set leaves it alone; remove_member_role refuses the last role.
create or replace function ${toRole}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_tenant ${tenant.idType} := coalesce(new.${t}, old.${t});
  v_user uuid := coalesce(new.${u}, old.${u});
  v_primary text;
begin
  select r."role" into v_primary from ${mr} r
  where r.${t} = v_tenant and r.${u} = v_user
  order by array_position(${ranks}, r."role"), r."role"
  limit 1;
  if v_primary is not null then
    perform set_config(${SYNC}, 'on', true);
    update ${m} m set ${role} = v_primary
    where m.${t} = v_tenant and m.${u} = v_user and m.${role}::text is distinct from v_primary;
    perform set_config(${SYNC}, '', true);
  end if;
  return null;
end;
$$;
revoke execute on function ${toRole}() from public, anon, authenticated;
drop trigger if exists ${tenant.trigger("membership_role_primary")} on ${mr};
create trigger ${tenant.trigger("membership_role_primary")} after insert or delete on ${mr}
  for each row execute function ${toRole}();
`;
}

/** The read policy on `membership_roles`, after the member functions exist. */
export function membershipRolesPolicy(tenant: BlockSqlContext): string {
  if (!manyRoles(tenant)) {
    return "";
  }

  const mr = membershipRolesTable(tenant);
  const t = tenant.col("memberships", "tenant");
  const u = tenant.col("memberships", "user");

  return `
${renderPolicy(makePolicy({ table: mr, name: "bsb_membership_roles_read", command: "select", roles: ["authenticated"], using: `${u} = (select auth.uid()) or ${t} in (select ${tenant.scope.members()})` }), { drop: true, target: mr })}
`;
}

/**
 * `organization_member_roles(organization, member)`: the member's roles,
 * highest-ranked first, or null when they aren't a member.
 */
export function memberRolesFunction(
  tenant: BlockSqlContext,
  roleName: string,
  filter: string,
): string {
  const m = tenant.table("memberships");
  const t = tenant.col("memberships", "tenant");
  const u = tenant.col("memberships", "user");
  const fn = tenant.fn("organization_member_roles");
  const id = tenant.idType;

  const body = manyRoles(tenant)
    ? `  select (
    select array_agg(r."role" order by array_position(${rankArray(tenant)}, r."role"), r."role")
    from ${membershipRolesTable(tenant)} r where r.${t} = m.${t} and r.${u} = m.${u}
  )
  from ${m} m where m.${t} = organization_member_roles.organization and m.${u} = organization_member_roles.member${filter}`
    : `  select array[${roleName}]::text[]
  from ${m} m where m.${t} = organization_member_roles.organization and m.${u} = organization_member_roles.member${filter}`;

  return `
-- The roles of a user in a tenant, highest-ranked first, or null when they
-- aren't a member.
create or replace function ${fn}(organization ${id}, member uuid)
returns text[]
language sql
stable
security definer
set search_path = ''
as $$
${body}
$$;
revoke execute on function ${fn}(${id}, uuid) from public, anon, authenticated;
grant execute on function ${fn}(${id}, uuid) to service_role;
`;
}
