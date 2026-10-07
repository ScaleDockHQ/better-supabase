import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";
import {
  accessModel,
  MODULE_PERMISSIONS,
  permdockPlatformRoles,
  roleNames,
  roleScopeIs,
} from "./access-model.ts";
import { roleValue, tenantRoleScope } from "./organizations.ts";
import { roleThrough, roleThroughTable } from "./tenant.ts";

/**
 * The catalog role id for a key or id, in `scope`, among `tenant`'s roles
 * when given; `roleValue` in other models.
 */
function roleIn(
  ctx: ModuleContext,
  expr: string,
  scope: "tenant" | "platform",
  tenant?: string,
): string {
  if (accessModel(ctx) !== "catalog") return roleValue(ctx, expr, tenant);
  const scoped = roleScopeIs(ctx, "r", scope);
  if (!scoped) return roleValue(ctx, expr, tenant);
  const access = ctx.of("access");
  const rid = access.col("roles", "id");
  const key = access.col("roles", "key");
  const text = `(${expr})::text`;
  const own = tenantRoleScope(ctx, tenant);
  return `(select r.${rid} from ${access.table("roles")} r where (r.${rid}::text = ${text} or r.${key} = ${text}) and ${scoped}${own.where} order by (r.${rid}::text = ${text}) desc${own.order} limit 1)`;
}

/** Where an accepted platform invitation assigns its role, and the checks around it. */
export interface PlatformAssignment {
  /** The stored role for a role name or id; null when it is unknown. */
  value(expr: string): string;
  /** The assignment table's role value for an invitation's stored role. */
  assign(stored: string): string;
  /** Whether `member` may assign the stored role `stored`; `undefined` for no ceiling. */
  canAssign(member: string, stored: string): string | undefined;
  inviterCanAssign(member: string, stored: string): string | undefined;
  readonly table: string;
  readonly user: string;
  readonly role: string;
  /** Whether the inviter's authority can be checked again at accept. */
  readonly recheck: boolean;
}

/**
 * Why `sql.modules.invitations.options.platformRoles.through` needs `where`:
 * its table also holds the tenant roles of
 * `sql.modules.tenant.options.roleThrough`. `undefined` when it doesn't.
 */
export function platformRolesProblem(ctx: ModuleContext): string | undefined {
  const through = permdockPlatformRoles(ctx)?.through;
  if (!through || through.where) return undefined;
  if (roleThroughTable(ctx.of("tenant"))?.table !== through.table)
    return undefined;
  return `sql.modules.invitations.options.platformRoles.through.where: ${through.table} also holds the tenant roles (sql.modules.tenant.options.roleThrough), so name the platform roles with a condition such as "{row}.scope = 'platform'"`;
}

export function platformAssignment(ctx: ModuleContext): PlatformAssignment {
  const permdock = permdockPlatformRoles(ctx);
  if (permdock) {
    const through = permdock.through;
    const problem = platformRolesProblem(ctx);
    if (problem) throw new TypeError(problem);
    const platformOnly = through?.where
      ? ` and (${through.where.replaceAll("{row}", "r")})`
      : "";
    const name = (stored: string) =>
      through
        ? `(select r.${through.column}::text from ${through.table} r where r.${through.id}::text = (${stored})::text)`
        : `(${stored})::text`;
    return {
      value: (expr) =>
        through
          ? `(select r.${through.id} from ${through.table} r where (r.${through.id}::text = (${expr})::text or r.${through.column}::text = (${expr})::text)${platformOnly} order by (r.${through.id}::text = (${expr})::text) desc limit 1)`
          : expr,
      assign(stored) {
        return this.value(stored);
      },
      canAssign: (member, stored) =>
        permdock.canAssign === undefined
          ? undefined
          : `coalesce((${permdock.canAssign.replaceAll("{user}", member).replaceAll("{role}", name(stored))}), false)`,
      inviterCanAssign: (member, stored) => {
        const template = permdock.canAssign?.includes("{user}")
          ? permdock.canAssign
          : permdock.canAssignFor;
        return template === undefined
          ? undefined
          : `coalesce((${template.replaceAll("{user}", member).replaceAll("{role}", name(stored))}), false)`;
      },
      table: permdock.table,
      user: permdock.user,
      role: permdock.role,
      recheck: false,
    };
  }
  const access = ctx.of("access");
  return {
    value: (expr) => roleIn(ctx, expr, "platform"),
    assign: (stored) => roleValue(ctx, stored, undefined, false),
    canAssign: (member, stored) =>
      `better_supabase.platform_can_assign(${member}, ${stored}::text)`,
    inviterCanAssign: (member, stored) =>
      `better_supabase.platform_can_assign(${member}, ${stored}::text)`,
    table: access.table("platformAssignments"),
    user: access.col("platformAssignments", "user"),
    role: access.col("platformAssignments", "role"),
    recheck: true,
  };
}

/**
 * The `bs_role_scope` trigger on `platformRoles.table` under the `permdock`
 * model: with `platformRoles.through.where`, every write (the service role's
 * too) stores a role that the condition names. Removed when `where` is unset.
 */
export function platformRoleScope(ctx: ModuleContext): string {
  const permdock = permdockPlatformRoles(ctx);
  if (!permdock) return "";
  const through = permdock.through;
  const fn = ctx.fn("platform_role_scope");
  const trigger = ctx.trigger("role_scope");
  if (!through?.where) {
    return `
drop trigger if exists ${trigger} on ${permdock.table};
drop function if exists ${fn}();
`;
  }
  return `
-- sql.modules.invitations.options.platformRoles.through.where names the
-- platform roles. Every write to ${permdock.table} stores one of them,
-- whoever writes it: a client policy, the service role or an admin connection.
create or replace function ${fn}()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.${permdock.role} is not null and not exists (
    select 1 from ${through.table} r
    where r.${through.id}::text = new.${permdock.role}::text and (${through.where.replaceAll("{row}", "r")})
  ) then
    raise exception 'Role % is not a platform role', new.${permdock.role}
      using errcode = '23514', hint = 'PLATFORM_ROLE_SCOPE';
  end if;
  return new;
end;
$$;
revoke execute on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${permdock.table};
create trigger ${trigger} before insert or update of ${permdock.role} on ${permdock.table}
  for each row execute function ${fn}();
`;
}

export const invitePlatform = (ctx: ModuleContext): string =>
  ctx.permission(
    "invitePlatform",
    MODULE_PERMISSIONS.invitations.invitePlatform,
  );

/**
 * `invitee_role` as the tenant table stores it, within the tenant in the
 * `tenant` variable, and the condition that it is unknown.
 */
export function tenantRole(ctx: ModuleContext): {
  readonly stored: string;
  readonly unknownRole: string;
} {
  const model = accessModel(ctx);
  const stored = roleIn(ctx, "invitee_role", "tenant", "tenant");
  const through = roleThrough(ctx.of("tenant")) !== undefined;
  const unknownRole =
    model === "catalog" || through
      ? `${stored} is null`
      : model === "roles"
        ? `not (invitee_role = any (array[${roleNames(ctx).map(sqlString).join(", ")}]::text[]))`
        : "false";
  return { stored, unknownRole };
}
