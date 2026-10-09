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
    "onboarding.*",
    "inbox.*",
    "ai_chat.*",
    "ai.*",
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
    "onboarding.read",
    "inbox.read",
    "inbox.reply",
    "ai_chat.read",
    "ai_chat.create",
    "ai_chat.share",
    "ai.read",
    "ai.create",
    "ai.share",
  ],
  viewer: ["organization.read"],
};

/**
 * The permission key each module action checks by default, overridable per
 * module in `sql.modules.<name>.permissions`. Keys are `<area>.<verb>`, with `read`
 * for viewing; platform-wide actions use the `platform` area or a key that
 * `is_platform()` checks. The AI blocks other than ai-chat check `ai.*` keys;
 * before 0.7 they checked the `ai_chat.*` ones, which `AI_KEY_ALIASES` still
 * accepts.
 */
export const MODULE_PERMISSIONS = {
  organizations: {
    update: "organization.update",
    delete: "organization.delete",
    removeMember: "members.remove",
    suspendMember: "members.remove",
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
  "webhooks-in": {
    create: "webhooks.manage",
    update: "webhooks.manage",
    delete: "webhooks.manage",
    view: "webhooks.read",
  },
  "api-keys": { manage: "api_keys.manage", own: "api_keys.own" },
  settings: {
    read: "settings.read",
    update: "settings.update",
    platform: "settings.manage",
  },
  usage: { read: "usage.read", record: "usage.record" },
  billing: {
    read: "billing.read",
    manage: "billing.manage",
    viewAll: "billing.read",
  },
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
  onboarding: { read: "onboarding.read", complete: "onboarding.complete" },
  announcements: { manage: "announcements.manage" },
  waitlist: { manage: "waitlist.manage", invite: "members.invite" },
  flags: { manage: "flags.manage" },
  workflows: {
    read: "workflow.read",
    run: "workflow.run",
    admin: "workflow.admin",
  },
  "workflow-builder": {
    read: "workflow.read",
    run: "workflow.run",
    edit: "workflow.edit",
    publish: "workflow.publish",
    admin: "workflow.admin",
  },
  inbox: {
    read: "inbox.read",
    reply: "inbox.reply",
    assign: "inbox.assign",
    manage: "inbox.manage",
  },
  "ai-chat": {
    read: "ai_chat.read",
    create: "ai_chat.create",
    share: "ai_chat.share",
    moderate: "ai_chat.moderate",
    admin: "ai_chat.admin",
  },
  "ai-files": { upload: "ai.create", manage: "ai.admin" },
  knowledge: {
    read: "ai.read",
    write: "ai.create",
    manage: "ai.admin",
  },
  memory: { read: "ai.read", manage: "ai.admin" },
  agents: {
    read: "ai.read",
    create: "ai.create",
    publish: "ai.share",
    moderate: "ai.moderate",
  },
  connectors: {
    read: "ai.read",
    use: "ai.create",
    manage: "ai.admin",
  },
  "ai-tasks": { create: "ai.create", manage: "ai.admin" },
  "ai-providers": { use: "ai.create", manage: "ai.admin" },
} as const;

/**
 * Where each module action checks its key: `tenant` through `member_can`,
 * `can` or `tenant_ids_with` (a provider's `idsWith`), and `platform`
 * through `is_platform` or `platform_can` (a provider's `isPlatform`).
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
    suspendMember: "tenant",
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
  "webhooks-in": {
    create: "tenant",
    update: "tenant",
    delete: "tenant",
    view: "tenant",
  },
  "api-keys": { manage: "tenant", own: "tenant" },
  settings: { read: "tenant", update: "tenant", platform: "platform" },
  usage: { read: "tenant", record: "tenant" },
  billing: { read: "tenant", manage: "tenant", viewAll: "platform" },
  comments: {
    read: "tenant",
    create: "tenant",
    moderate: "tenant",
    activity: "tenant",
  },
  attachments: { read: "tenant", upload: "tenant", manage: "tenant" },
  "data-lifecycle": { export: "tenant", delete: "tenant" },
  sso: { manage: "tenant" },
  onboarding: { read: "tenant", complete: "tenant" },
  announcements: { manage: "platform" },
  waitlist: { manage: "platform", invite: "tenant" },
  flags: { manage: "platform" },
  workflows: { read: "tenant", run: "tenant", admin: "tenant" },
  "workflow-builder": {
    read: "tenant",
    run: "tenant",
    edit: "tenant",
    publish: "tenant",
    admin: "tenant",
  },
  inbox: {
    read: "tenant",
    reply: "tenant",
    assign: "tenant",
    manage: "tenant",
  },
  "ai-chat": {
    read: "tenant",
    create: "tenant",
    share: "tenant",
    moderate: "tenant",
    admin: "tenant",
  },
  "ai-files": { upload: "tenant", manage: "tenant" },
  knowledge: { read: "tenant", write: "tenant", manage: "tenant" },
  memory: { read: "tenant", manage: "tenant" },
  agents: {
    read: "tenant",
    create: "tenant",
    publish: "tenant",
    moderate: "tenant",
  },
  connectors: { read: "tenant", use: "tenant", manage: "tenant" },
  "ai-tasks": { create: "tenant", manage: "tenant" },
  "ai-providers": { use: "tenant", manage: "tenant" },
};

/**
 * Deprecated since 0.7: a grant of `ai_chat.<verb>` (or `ai_chat.*`) still
 * answers the `ai.<verb>` key the non-chat AI blocks check, in the `roles`
 * and `catalog` models (`permission_matches`). Removed in 0.8.
 */
export const AI_KEY_ALIASES: Readonly<Record<string, string>> = {
  "ai.read": "ai_chat.read",
  "ai.create": "ai_chat.create",
  "ai.share": "ai_chat.share",
  "ai.moderate": "ai_chat.moderate",
  "ai.admin": "ai_chat.admin",
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
 * `sql.modules.invitations.options.platformRoles` under the `provider` model:
 * the app's table of platform role assignments, so platform invitations
 * insert into it.
 */
export interface ProviderPlatformRoles {
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
    /** A condition on the roles row `{row}` that holds for platform roles only. */
    readonly where?: string;
  };
  /** A SQL template with `{user}` and `{role}` (the role name) deciding who assigns which platform role. */
  readonly canAssign?: string;
  readonly canAssignFor?: string;
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

/** The `provider` model's platform role table, or `undefined` without one. */
export function providerPlatformRoles(
  ctx: ModuleContext,
): ProviderPlatformRoles | undefined {
  if (accessModel(ctx) !== "provider" || !ctx.installed("invitations")) {
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
    (value["canAssign"] !== undefined &&
      typeof value["canAssign"] !== "string") ||
    (value["canAssignFor"] !== undefined &&
      (typeof value["canAssignFor"] !== "string" ||
        !value["canAssignFor"].includes("{user}")))
  ) {
    throw new TypeError(
      `${where} must be { table: "schema.table", user: "<user column>", role: "<role column>", through?: { table, id, column }, canAssign?: "<SQL template>", canAssignFor?: "<SQL template with {user}>" }`,
    );
  }
  const user = quotedRef(where, value["table"], value["user"]);
  const role = quotedRef(where, value["table"], value["role"]);
  const through = value["through"];
  let lookup: ProviderPlatformRoles["through"];
  if (through !== undefined) {
    if (
      !isPlain(through) ||
      typeof through["table"] !== "string" ||
      typeof through["id"] !== "string" ||
      typeof through["column"] !== "string" ||
      (through["where"] !== undefined &&
        (typeof through["where"] !== "string" ||
          !through["where"].includes("{row}")))
    ) {
      throw new TypeError(
        `${where}.through must be { table: "schema.table", id: "<key column>", column: "<role name column>", where?: "<condition on {row}>" }`,
      );
    }
    const id = quotedRef(`${where}.through`, through["table"], through["id"]);
    lookup = {
      table: id.table,
      id: id.column,
      column: quotedRef(`${where}.through`, through["table"], through["column"])
        .column,
      ...(typeof through["where"] === "string"
        ? { where: through["where"] }
        : {}),
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
    ...(typeof value["canAssignFor"] === "string"
      ? { canAssignFor: value["canAssignFor"] }
      : {}),
  };
}

/** Whether the catalog has platform roles, and so platform invitations. */
export function hasPlatformRoles(ctx: ModuleContext): boolean {
  if (providerPlatformRoles(ctx)) return true;
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

type PermissionShorthand =
  | string
  | { readonly module: string; readonly action: string };

const MODULE_PERMISSION_SHORTHANDS: Readonly<
  Record<string, Readonly<Record<string, PermissionShorthand>>>
> = {
  organizations: { suspendMember: "removeMember" },
  invitations: { revoke: "invite", view: "invite" },
  audit: { viewAll: "view" },
  billing: { viewAll: "read" },
  waitlist: { invite: { module: "invitations", action: "invite" } },
  "webhooks-in": { create: "manage", update: "manage", delete: "manage" },
};

export function modulePermissionKey(
  ctx: ModuleContext,
  action: string,
  fallback: string,
): string {
  const shorthand = MODULE_PERMISSION_SHORTHANDS[ctx.module]?.[action];
  if (shorthand === undefined) return ctx.permissionKey(action, fallback);
  const target =
    typeof shorthand === "string"
      ? modulePermissionKey(ctx, shorthand, fallback)
      : modulePermissionKey(
          ctx.of(shorthand.module),
          shorthand.action,
          fallback,
        );
  return ctx.permissionKey(action, target);
}

export const modulePermission = (
  ctx: ModuleContext,
  action: string,
  fallback: string,
): string => sqlString(modulePermissionKey(ctx, action, fallback));
