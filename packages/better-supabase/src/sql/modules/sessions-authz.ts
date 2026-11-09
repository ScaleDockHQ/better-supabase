import type { BlockSqlContext } from "../context.ts";

/**
 * Statement-level bumps for a role's default permissions, platform assignments
 * and per-tenant overrides. A row trigger would bump once per changed key; one
 * statement bumps each holder once. Without the role bump, `hook_plan` `reuse`
 * keeps claims from before the default changed.
 */
export function roleAuthzBumps(ctx: BlockSqlContext): string {
  if (
    !ctx.installedModules.includes("permissions") ||
    !ctx.installedModules.includes("memberships")
  ) {
    return "";
  }

  const permissions = ctx.of("permissions");
  const memberships = ctx.of("memberships");

  if (!permissions.hasTable("rolePermissions")) {
    return "";
  }

  const members = memberships.table("memberships");
  const memberUser = memberships.col("memberships", "user");
  const memberRole = memberships.col("memberships", "role");
  const memberTenant = memberships.col("memberships", "tenant");
  const roles = permissions.table("rolePermissions");
  const roleCol = permissions.col("rolePermissions", "role");

  const holders = (from: string): string => `array(
    select m.${memberUser}
    from ${members} m
    where m.${memberRole} in (select ${roleCol} from ${from})
  )`;

  const statement = (
    name: string,
    event: "insert" | "update" | "delete",
    body: string,
    referencing: string,
  ): string => `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(${body});
  return null;
end;
$$;

revoke execute on function better_supabase.${name}() from public, anon, authenticated;

drop trigger if exists bsb_${name} on ${roles};
create trigger bsb_${name}
  after ${event} on ${roles}
  referencing ${referencing}
  for each statement execute function better_supabase.${name}();`;

  const platform = permissions.hasTable("platformAssignments")
    ? platformBumps(permissions)
    : "";

  const overrides = permissions.hasTable("overrides")
    ? overrideBumps(permissions, members, memberUser, memberRole, memberTenant)
    : "";

  return `
${statement(
  "bump_inserted_role_members",
  "insert",
  holders("changed"),
  "new table as changed",
)}
${statement(
  "bump_deleted_role_members",
  "delete",
  holders("changed"),
  "old table as changed",
)}
${statement(
  "bump_updated_role_members",
  "update",
  `array(
    select m.${memberUser}
    from ${members} m
    where m.${memberRole} in (
      select ${roleCol} from changed
      union
      select ${roleCol} from previous
    )
  )`,
  "new table as changed old table as previous",
)}
${platform}${overrides}`;
}

function platformBumps(permissions: ReturnType<BlockSqlContext["of"]>): string {
  const table = permissions.table("platformAssignments");
  const user = permissions.col("platformAssignments", "user");

  const one = (
    name: string,
    event: string,
    referencing: string,
    from: string,
  ): string => `
create or replace function better_supabase.${name}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(array(select ${user} from ${from}));
  return null;
end;
$$;

revoke execute on function better_supabase.${name}() from public, anon, authenticated;

drop trigger if exists bsb_${name} on ${table};
create trigger bsb_${name}
  after ${event} on ${table}
  referencing ${referencing}
  for each statement execute function better_supabase.${name}();`;

  return `${one("bump_inserted_platform_roles", "insert", "new table as changed", "changed")}
${one("bump_deleted_platform_roles", "delete", "old table as changed", "changed")}`;
}

function overrideBumps(
  permissions: ReturnType<BlockSqlContext["of"]>,
  members: string,
  memberUser: string,
  memberRole: string,
  memberTenant: string,
): string {
  const table = permissions.table("overrides");
  const tenant = permissions.col("overrides", "tenant");
  const role = permissions.col("overrides", "role");

  const body = (from: string): string => `array(
    select m.${memberUser}
    from ${members} m
    where (m.${memberTenant}, m.${memberRole}) in (
      select ${tenant}, ${role} from ${from}
    )
  )`;

  return `
create or replace function better_supabase.bump_override_members()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform better_supabase.bump_authz_versions(${body("changed")});
  return null;
end;
$$;

revoke execute on function better_supabase.bump_override_members() from public, anon, authenticated;

drop trigger if exists bsb_permission_overrides_bump_authz_versions on ${table};
drop trigger if exists bsb_bump_override_members_insert on ${table};
drop trigger if exists bsb_bump_override_members_update on ${table};
drop trigger if exists bsb_bump_override_members_delete on ${table};
create trigger bsb_bump_override_members_insert
  after insert on ${table}
  referencing new table as changed
  for each statement execute function better_supabase.bump_override_members();
create trigger bsb_bump_override_members_update
  after update on ${table}
  referencing new table as changed
  for each statement execute function better_supabase.bump_override_members();
create trigger bsb_bump_override_members_delete
  after delete on ${table}
  referencing old table as changed
  for each statement execute function better_supabase.bump_override_members();`;
}
