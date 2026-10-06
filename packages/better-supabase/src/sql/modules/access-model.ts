import type { AccessModuleConfig } from "../../config/modules.ts";
import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";

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
    "api_keys.*",
    "settings.*",
    "usage.*",
    "comments.*",
    "activity.read",
    "attachments.*",
    "organization.export",
  ],
  member: [
    "organization.read",
    "members.read",
    "notifications.read",
    "api_keys.own",
    "settings.read",
    "comments.read",
    "comments.create",
    "activity.read",
    "attachments.read",
    "attachments.upload",
  ],
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
  "webhooks-in": { manage: "webhooks.manage", view: "webhooks.read" },
  "api-keys": { manage: "api_keys.manage", own: "api_keys.own" },
  settings: { read: "settings.read", update: "settings.update" },
  usage: { read: "usage.read" },
  billing: { read: "billing.read", manage: "billing.manage" },
  comments: {
    read: "comments.read",
    create: "comments.create",
    moderate: "comments.moderate",
    activity: "activity.read",
  },
  "data-lifecycle": {
    export: "organization.export",
    delete: "organization.delete",
  },
  attachments: {
    read: "attachments.read",
    upload: "attachments.upload",
    manage: "attachments.manage",
  },
  sso: { manage: "sso.manage" },
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
  "webhooks-in": { manage: "tenant", view: "tenant" },
  "api-keys": { manage: "tenant", own: "tenant" },
  settings: { read: "tenant", update: "tenant" },
  usage: { read: "tenant" },
  billing: { read: "tenant", manage: "tenant" },
  comments: {
    read: "tenant",
    create: "tenant",
    moderate: "tenant",
    activity: "tenant",
  },
  attachments: { read: "tenant", upload: "tenant", manage: "tenant" },
  "data-lifecycle": { export: "tenant", delete: "tenant" },
  sso: { manage: "tenant" },
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

/**
 * `sql.modules.invitations.options.platformRoles` under the `permdock` model:
 * the app's table of platform role assignments (PermDock's `rls.roles`), so
 * platform invitations insert into it.
 */
export interface PermdockPlatformRoles {
  /** Quoted `schema.table`. */
  readonly table: string;
  /** Quoted columns. */
  readonly user: string;
  readonly role: string;
  /** The roles table the role column points into, quoted. */
  readonly through?: {
    readonly table: string;
    readonly id: string;
    readonly column: string;
  };
  /** A SQL template with `{user}` and `{role}` (the role name) deciding who assigns which platform role. */
  readonly canAssign?: string;
}

const isPlain = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

const quotedRef = (where: string, table: string, column: string) => {
  const parts = `${table}.${column}`.split(".");
  if (
    parts.length !== 3 ||
    parts.some((part) => !/^[A-Za-z_][A-Za-z0-9_$]*$/.test(part))
  ) {
    throw new TypeError(
      `${where}: "${table}" must be "schema.table" and "${column}" a column`,
    );
  }
  return {
    table: `${sqlIdent(parts[0]!)}.${sqlIdent(parts[1]!)}`,
    column: sqlIdent(parts[2]!),
  };
};

/** The `permdock` model's platform role table, or `undefined` without one. */
export function permdockPlatformRoles(
  ctx: ModuleContext,
): PermdockPlatformRoles | undefined {
  if (accessModel(ctx) !== "permdock" || !ctx.installed("invitations")) {
    return undefined;
  }
  const value = ctx.of("invitations").option("platformRoles");
  if (value === undefined) return undefined;
  const where = "sql.modules.invitations.options.platformRoles";
  if (
    !isPlain(value) ||
    typeof value["table"] !== "string" ||
    typeof value["user"] !== "string" ||
    typeof value["role"] !== "string" ||
    (value["canAssign"] !== undefined && typeof value["canAssign"] !== "string")
  ) {
    throw new TypeError(
      `${where} must be { table: "schema.table", user: "<user column>", role: "<role column>", through?: { table, id, column }, canAssign?: "<SQL template>" }`,
    );
  }
  const user = quotedRef(where, value["table"], value["user"]);
  const role = quotedRef(where, value["table"], value["role"]);
  const through = value["through"];
  let lookup: PermdockPlatformRoles["through"];
  if (through !== undefined) {
    if (
      !isPlain(through) ||
      typeof through["table"] !== "string" ||
      typeof through["id"] !== "string" ||
      typeof through["column"] !== "string"
    ) {
      throw new TypeError(
        `${where}.through must be { table: "schema.table", id: "<key column>", column: "<role name column>" }`,
      );
    }
    const id = quotedRef(`${where}.through`, through["table"], through["id"]);
    lookup = {
      table: id.table,
      id: id.column,
      column: quotedRef(`${where}.through`, through["table"], through["column"])
        .column,
    };
  }
  return {
    table: user.table,
    user: user.column,
    role: role.column,
    ...(lookup ? { through: lookup } : {}),
    ...(typeof value["canAssign"] === "string"
      ? { canAssign: value["canAssign"] }
      : {}),
  };
}

/** Whether the catalog has platform roles, and so platform invitations. */
export function hasPlatformRoles(ctx: ModuleContext): boolean {
  if (permdockPlatformRoles(ctx)) return true;
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
