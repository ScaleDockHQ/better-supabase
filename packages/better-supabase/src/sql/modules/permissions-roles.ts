import type { BlockSqlContext } from "../context.ts";

import { SERVICE_CALLER, fail, userGrant } from "../shared.ts";
import { OPERATIONS, accessModel, roleScopeIs } from "./permissions-model.ts";

/**
 * `list_roles` and `set_permission_override`: the catalog's tenant roles with
 * their keys in one tenant, and the per-tenant grant or deny of one key. Only
 * the catalog model with the overrides table renders them.
 */
export const rendersRoleFunctions = (ctx: BlockSqlContext): boolean =>
  accessModel(ctx) === "catalog" && ctx.hasTable("overrides");

export function catalogRoleFunctions(ctx: BlockSqlContext): string {
  const id = ctx.idType;

  if (!rendersRoleFunctions(ctx)) {
    return `
drop function if exists ${ctx.fn("list_roles")}(${id});
drop function if exists ${ctx.fn("set_permission_override")}(${id}, text, text, boolean);`;
  }

  const members = ctx.of("memberships");
  const m = members.table("memberships");
  const mTenant = members.col("memberships", "tenant");
  const mUser = members.col("memberships", "user");
  const mRole = members.col("memberships", "role");
  const roles = ctx.table("roles");
  const rId = ctx.col("roles", "id");
  const rKey = ctx.col("roles", "key");
  const perms = ctx.table("permissions");
  const pId = ctx.col("permissions", "id");
  const pKey = ctx.col("permissions", "key");
  const rp = ctx.table("rolePermissions");
  const rpRole = ctx.col("rolePermissions", "role");
  const rpPermission = ctx.col("rolePermissions", "permission");
  const o = ctx.table("overrides");
  const oTenant = ctx.col("overrides", "tenant");
  const oRole = ctx.col("overrides", "role");
  const oPermission = ctx.col("overrides", "permission");
  const oGranted = ctx.col("overrides", "granted");

  const listKey = ctx.permission(
    "listRoles",
    OPERATIONS["permissions.listRoles"],
  );

  const manageKey = ctx.permission(
    "setOverride",
    OPERATIONS["permissions.setOverride"],
  );

  const tenantRole = roleScopeIs(ctx, "r", "tenant");
  const scoped = tenantRole ? ` and ${tenantRole}` : "";

  const memberCan = (tenant: string, key: string): string =>
    `coalesce(better_supabase.member_can(auth.uid(), ${tenant}, ${key}), false)`;

  // One role in one tenant: deny beats grant beats the role default, as
  // member_can decides for a member holding it.
  const roleJson = (tenant: string): string => `jsonb_build_object(
      'id', r.${rId},
      'key', r.${rKey},
      'members', (select count(*) from ${m} mm where mm.${mTenant} = ${tenant} and mm.${mRole} = r.${rId}),
      'default_permissions', coalesce((
        select jsonb_agg(p.${pKey} order by p.${pKey})
        from ${rp} x join ${perms} p on p.${pId} = x.${rpPermission}
        where x.${rpRole} = r.${rId}
      ), '[]'::jsonb),
      'permissions', coalesce((
        select jsonb_agg(p.${pKey} order by p.${pKey})
        from ${perms} p
        where coalesce(
          (select bool_and(ov.${oGranted}) from ${o} ov
            where ov.${oTenant} = ${tenant} and ov.${oRole} = r.${rId} and ov.${oPermission} = p.${pId}),
          exists (select 1 from ${rp} x where x.${rpRole} = r.${rId} and x.${rpPermission} = p.${pId})
        )
      ), '[]'::jsonb),
      'overrides', coalesce((
        select jsonb_agg(jsonb_build_object('permission', p.${pKey}, 'granted', ov.${oGranted}) order by p.${pKey})
        from ${o} ov join ${perms} p on p.${pId} = ov.${oPermission}
        where ov.${oTenant} = ${tenant} and ov.${oRole} = r.${rId}
      ), '[]'::jsonb)
    )`;

  return `
-- The tenant roles of the catalog with their keys in one tenant: the role's
-- defaults, the keys after this tenant's overrides, the overrides and how many
-- members hold the role.
create or replace function ${ctx.fn("list_roles")}(tenant ${id})
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not (${SERVICE_CALLER} or ${memberCan("list_roles.tenant", listKey)}) then
    ${fail("PERMISSIONS_FORBIDDEN", "Not allowed to read roles")}
  end if;
  return coalesce((
    select jsonb_agg(${roleJson("list_roles.tenant")} order by r.${rKey})
    from ${roles} r
    where true${scoped}
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${ctx.fn("list_roles")}(${id})`)}

-- Grants (true) or denies (false) one key to a role in one tenant; null
-- clears the override, so the role's default applies again. Members change
-- only roles they could assign, and only keys they hold themselves.
-- Errors carry a code in the hint: PERMISSIONS_FORBIDDEN, PERMISSIONS_ROLE_UNKNOWN,
-- PERMISSIONS_KEY_UNKNOWN, PERMISSIONS_ROLE_CEILING, PERMISSIONS_KEY_CEILING,
-- PERMISSIONS_SELF_LOCKOUT.
create or replace function ${ctx.fn("set_permission_override")}(tenant ${id}, role text, permission text, granted boolean)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_role uuid;
  v_permission uuid;
  v_service boolean := ${SERVICE_CALLER};
begin
  if not (v_service or ${memberCan("tenant", manageKey)}) then
    ${fail("PERMISSIONS_FORBIDDEN", "Not allowed to change role permissions")}
  end if;
  select r.${rId} into v_role from ${roles} r
  where (r.${rId}::text = role or r.${rKey} = role)${scoped};
  if v_role is null then
    ${fail("PERMISSIONS_ROLE_UNKNOWN", "Unknown role", "P0002")}
  end if;
  select p.${pId} into v_permission from ${perms} p where p.${pKey} = permission;
  if v_permission is null then
    ${fail("PERMISSIONS_KEY_UNKNOWN", "Unknown permission", "P0002")}
  end if;
  if not v_service then
    if not better_supabase.can_assign(tenant, v_role::text) then
      ${fail("PERMISSIONS_ROLE_CEILING", "That role is above your own")}
    end if;
    if not ${memberCan("tenant", "permission")} then
      ${fail("PERMISSIONS_KEY_CEILING", "You can only change keys you hold")}
    end if;
    if granted is distinct from true and permission = ${manageKey} and exists (
      select 1 from ${m} mm where mm.${mTenant} = tenant and mm.${mUser} = auth.uid() and mm.${mRole} = v_role
    ) then
      ${fail("PERMISSIONS_SELF_LOCKOUT", "You cannot take this key from your own role")}
    end if;
  end if;
  if granted is null then
    delete from ${o} ov
    where ov.${oTenant} = tenant and ov.${oRole} = v_role and ov.${oPermission} = v_permission;
  else
    insert into ${o} (${oTenant}, ${oRole}, ${oPermission}, ${oGranted})
    values (tenant, v_role, v_permission, granted)
    on conflict (${oTenant}, ${oRole}, ${oPermission}) do update set ${oGranted} = excluded.${oGranted};
  end if;
  return (select ${roleJson("set_permission_override.tenant")} from ${roles} r where r.${rId} = v_role);
end;
$$;
${userGrant(`${ctx.fn("set_permission_override")}(${id}, text, text, boolean)`)}`;
}
