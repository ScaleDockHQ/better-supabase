import type { AccessModuleConfig } from "../../config/modules.ts";
import type { ModuleContext } from "../context.ts";

import { sqlString } from "../../core/template.ts";

export type AccessModel = NonNullable<AccessModuleConfig["model"]>;

/**
 * The `roles` model's defaults. Module actions name these keys (see
 * `MODULE_PERMISSIONS`); `*` grants everything and `prefix.*` a prefix.
 */
export const DEFAULT_ROLES: Readonly<Record<string, readonly string[]>> = {
  owner: ["*"],
  admin: [
    "organization.read",
    "organization.update",
    "members.*",
    "audit.read",
    "webhooks.*",
    "notifications.*",
    "billing.*",
  ],
  member: ["organization.read", "members.read", "notifications.read"],
  viewer: ["organization.read"],
};

/**
 * The permission key each module action checks by default, overridable per
 * module in `sql.modules.<name>.permissions`. Keys are `<area>.<verb>`, with `read`
 * for viewing; platform-wide actions use the `platform` area or a key that
 * `is_platform()` checks.
 */
export const MODULE_PERMISSIONS = {
  organizations: {
    update: "organization.update",
    delete: "organization.delete",
    removeMember: "members.remove",
    updateRole: "members.update_role",
    transferOwnership: "organization.transfer_ownership",
  },
  invitations: {
    invite: "members.invite",
    revoke: "members.invite",
    view: "members.invite",
    invitePlatform: "platform.invite",
  },
  audit: { view: "audit.read", viewAll: "audit.read" },
  "support-sessions": {
    start: "support.start",
    view: "support.read",
    revoke: "support.revoke",
  },
  notifications: { send: "notifications.send", read: "notifications.read" },
  "webhooks-out": { manage: "webhooks.manage", view: "webhooks.read" },
} as const;

/**
 * Where each module action checks its key: `tenant` through `member_can`,
 * `can` or `tenant_ids_with` (PermDock's `permitted_<scope>_ids`), and
 * `platform` through `is_platform` or `platform_can` (`permdock_has`).
 */
export const MODULE_PERMISSION_SCOPES: {
  readonly [M in keyof typeof MODULE_PERMISSIONS]: {
    readonly [A in keyof (typeof MODULE_PERMISSIONS)[M]]: "tenant" | "platform";
  };
} = {
  organizations: {
    update: "tenant",
    delete: "tenant",
    removeMember: "tenant",
    updateRole: "tenant",
    transferOwnership: "tenant",
  },
  invitations: {
    invite: "tenant",
    revoke: "tenant",
    view: "tenant",
    invitePlatform: "platform",
  },
  audit: { view: "tenant", viewAll: "platform" },
  "support-sessions": {
    start: "platform",
    view: "platform",
    revoke: "platform",
  },
  notifications: { send: "tenant", read: "tenant" },
  "webhooks-out": { manage: "tenant", view: "tenant" },
};

export function accessModel(ctx: ModuleContext): AccessModel {
  return ctx.modules.access?.model ?? "roles";
}

export function rolesOf(
  ctx: ModuleContext,
): Readonly<Record<string, readonly string[]>> {
  return ctx.modules.access?.roles ?? DEFAULT_ROLES;
}

export const roleNames = (ctx: ModuleContext): readonly string[] =>
  Object.keys(rolesOf(ctx));

/**
 * The scope name tenants use in `can(scope, id, permission)`
 * (`sql.modules.access.options.scope`, default `organization`). `tenant` is
 * accepted too.
 */
export const tenantScope = (ctx: ModuleContext): string =>
  ctx.of("access").text("scope", "organization");

/** Whether the catalog has platform roles, and so platform invitations. */
export function hasPlatformRoles(ctx: ModuleContext): boolean {
  return (
    accessModel(ctx) === "catalog" &&
    ctx.of("access").hasTable("platformAssignments")
  );
}

/**
 * Whether catalog role row `alias` is a tenant or a platform role, or
 * `undefined` when roles carry no scope. Managed catalogs have a `scope`
 * column; an adopted one maps `roles.scope` and names its values in
 * `sql.modules.access.options.tenantRoleScope` and `platformRoleScope`.
 */
export function roleScopeIs(
  ctx: ModuleContext,
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
