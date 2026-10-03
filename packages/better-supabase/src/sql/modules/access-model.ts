import type { AccessKitConfig } from "../../config/kits.ts";
import type { KitContext } from "../context.ts";

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
  notifications: { send: "notifications.send" },
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
