import type { AccessKitConfig } from "../../config/kits.ts";
import type { KitContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

export type AccessModel = NonNullable<AccessKitConfig["model"]>;

/**
 * The `roles` model's defaults. Kit actions name these keys (see
 * `KIT_PERMISSIONS`); `*` grants everything and `prefix.*` a prefix.
 */
export const DEFAULT_ROLES: Readonly<Record<string, readonly string[]>> = {
  owner: ["*"],
  admin: [
    "organization.read",
    "organization.update",
    "members.*",
    "audit.view",
    "webhooks.*",
    "notifications.*",
    "billing.*",
  ],
  member: ["organization.read", "members.read", "notifications.read"],
  viewer: ["organization.read"],
};

/** The permission key each kit action checks by default, overridable per module in `kits.<name>.permissions`. */
export const KIT_PERMISSIONS = {
  organizations: {
    update: "organization.update",
    delete: "organization.delete",
    removeMember: "members.remove",
    updateRole: "members.update_role",
    transferOwnership: "ownership.transfer",
  },
  invitations: {
    invite: "members.invite",
    revoke: "members.invite",
    view: "members.invite",
  },
  audit: { view: "audit.view" },
  "support-sessions": { start: "support.start", view: "support.view" },
  notifications: { send: "notifications.send", read: "notifications.read" },
  "webhooks-out": { manage: "webhooks.manage", view: "webhooks.view" },
} as const;

export function accessModel(ctx: KitContext): AccessModel {
  return ctx.kits.access?.model ?? "roles";
}

export function rolesOf(
  ctx: KitContext,
): Readonly<Record<string, readonly string[]>> {
  return ctx.kits.access?.roles ?? DEFAULT_ROLES;
}

export const roleNames = (ctx: KitContext): readonly string[] =>
  Object.keys(rolesOf(ctx));

/**
 * The scope name tenants use in `can(scope, id, permission)`
 * (`kits.access.options.scope`, default `organization`). `tenant` is
 * accepted too.
 */
export const tenantScope = (ctx: KitContext): string =>
  ctx.of("access").text("scope", "organization");

/** Whether the catalog has platform roles, and so platform invitations. */
export function hasPlatformRoles(ctx: KitContext): boolean {
  return (
    accessModel(ctx) === "catalog" &&
    ctx.of("access").hasTable("platformAssignments")
  );
}

/**
 * Whether catalog role row `alias` is a tenant or a platform role, or
 * `undefined` when roles carry no scope. Managed catalogs have a `scope`
 * column; an adopted one maps `roles.scope` and names its values in
 * `kits.access.options.tenantRoleScope` and `platformRoleScope`.
 */
export function roleScopeIs(
  ctx: KitContext,
  alias: string,
  scope: "tenant" | "platform",
): string | undefined {
  if (accessModel(ctx) !== "catalog") return undefined;
  const access = ctx.of("access");
  if (!access.manages && access.config.columns["roles"]?.["scope"] == null) {
    return undefined;
  }
  const value =
    scope === "tenant"
      ? access.text("tenantRoleScope", "tenant")
      : access.text("platformRoleScope", "platform");
  return `${alias}.${access.col("roles", "scope")}::text = ${sqlString(value)}`;
}
