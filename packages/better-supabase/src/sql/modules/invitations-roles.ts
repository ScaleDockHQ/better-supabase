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
import { roleThrough } from "./tenant.ts";

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

export function platformAssignment(ctx: ModuleContext): PlatformAssignment {
  const permdock = permdockPlatformRoles(ctx);
  if (permdock) {
    const through = permdock.through;
    const name = (stored: string) =>
      through
        ? `(select r.${through.column}::text from ${through.table} r where r.${through.id}::text = (${stored})::text)`
        : `(${stored})::text`;
    return {
      value: (expr) =>
        through
          ? `(select r.${through.id} from ${through.table} r where r.${through.id}::text = (${expr})::text or r.${through.column}::text = (${expr})::text order by (r.${through.id}::text = (${expr})::text) desc limit 1)`
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
    assign: (stored) => roleValue(ctx, stored),
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
