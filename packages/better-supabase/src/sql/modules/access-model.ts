import type { AccessBlockConfig } from "../../config/blocks.ts";
import type { ModuleContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";

export type AccessModel = NonNullable<AccessBlockConfig["model"]>;

/**
 * The `roles` model's defaults. Module actions name these keys (see
 * `OPERATIONS`); `*` grants everything and `prefix.*` a prefix.
 */
export const DEFAULT_ROLES: Readonly<Record<string, readonly string[]>> = {
  owner: ["*"],
  admin: [
    "organization.read",
    "organization.update",
    "members.*",
    "audit.read",
    "audit.revert",
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
    "tags.*",
    "teams.*",
    "custom_fields.*",
    "share_links.*",
    "reminders.*",
    "imports.*",
    "views.*",
    "relations.*",
    "bulk.*",
    "search.*",
    "metrics.*",
    "calendar.*",
    "bookings.*",
    "versions.*",
    "trash.*",
    "reactions.*",
    "approvals.*",
    "access_requests.*",
    "documents.*",
    "drive.*",
    "forms.*",
    "signatures.*",
    "templates.*",
    "time_tracking.*",
    "service_principals.*",
    "pipelines.*",
    "parties.*",
    "engagements.*",
    "deals.*",
    "work_items.*",
    "quotes.*",
    "invoices.*",
    "sla.*",
    "targets.*",
    "hiring.*",
    "employees.*",
    "collections.*",
    "domains.*",
    "rules.*",
    "reviews.*",
    "leave.*",
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
    "custom_fields.read",
    "teams.read",
    "tags.read",
    "tags.apply",
    "share_links.read",
    "reminders.read",
    "views.read",
    "relations.read",
    "bulk.run",
    "search.read",
    "metrics.read",
    "calendar.read",
    "calendar.write",
    "bookings.read",
    "bookings.create",
    "versions.read",
    "versions.create",
    "versions.restore",
    "trash.read",
    "trash.create",
    "trash.restore",
    "reactions.read",
    "reactions.create",
    "approvals.read",
    "approvals.request",
    "access_requests.create",
    "documents.read",
    "documents.write",
    "drive.read",
    "drive.create",
    "forms.read",
    "forms.submit",
    "signatures.read",
    "signatures.request",
    "templates.read",
    "templates.apply",
    "time_tracking.track",
    "leave.request",
    "pipelines.read",
    "parties.read",
    "parties.write",
    "engagements.read",
    "engagements.write",
    "deals.read",
    "deals.write",
    "work_items.read",
    "work_items.write",
    "quotes.read",
    "quotes.write",
    "invoices.read",
    "sla.read",
    "targets.read",
    "employees.read",
    "collections.read",
    "collections.write",
    "domains.read",
    "rules.read",
  ],
  viewer: ["organization.read"],
};

/**
 * The permission key each operation checks by default, keyed
 * `<module>.<action>`. `blocks.<name>.permissions` renames a key per module,
 * `authorization.operations` overrides it for a provider, and the access
 * module's `operation_permission(op)` answers the result in SQL. Keys are
 * `<area>.<verb>`, with `read` for viewing; platform-wide actions use the
 * `platform` area or a key that `is_platform()` checks. The AI blocks other
 * than ai-chat check `ai.*` keys.
 */
export const OPERATIONS = {
  "organizations.update": "organization.update",
  "organizations.delete": "organization.delete",
  "organizations.removeMember": "members.remove",
  "organizations.suspendMember": "members.remove",
  "organizations.updateRole": "members.update_role",
  "organizations.transferOwnership": "organization.transfer_ownership",
  "invitations.invite": "members.invite",
  "invitations.revoke": "members.invite",
  "invitations.view": "members.invite",
  "invitations.invitePlatform": "platform.invite",
  "audit.view": "audit.read",
  "audit.viewAll": "audit.read",
  "audit.revert": "audit.revert",
  "support-sessions.start": "support.start",
  "support-sessions.view": "support.read",
  "support-sessions.revoke": "support.revoke",
  "notifications.send": "notifications.send",
  "notifications.read": "notifications.read",
  "webhooks-out.manage": "webhooks.manage",
  "webhooks-out.view": "webhooks.read",
  "webhooks-in.create": "webhooks.manage",
  "webhooks-in.update": "webhooks.manage",
  "webhooks-in.delete": "webhooks.manage",
  "webhooks-in.view": "webhooks.read",
  "api-keys.manage": "api_keys.manage",
  "api-keys.own": "api_keys.own",
  "settings.read": "settings.read",
  "settings.update": "settings.update",
  "settings.platform": "settings.manage",
  "usage.read": "usage.read",
  "usage.record": "usage.record",
  "billing.read": "billing.read",
  "billing.manage": "billing.manage",
  "billing.viewAll": "billing.read",
  "comments.read": "comments.read",
  "comments.create": "comments.create",
  "comments.moderate": "comments.moderate",
  "comments.activity": "activity.read",
  "data-lifecycle.export": "organization.export",
  "data-lifecycle.delete": "organization.delete",
  "data-lifecycle.cancelDelete": "organization.delete",
  "attachments.read": "attachments.read",
  "attachments.upload": "attachments.upload",
  "attachments.manage": "attachments.manage",
  "sso.manage": "sso.manage",
  "onboarding.read": "onboarding.read",
  "onboarding.complete": "onboarding.complete",
  "announcements.manage": "announcements.manage",
  "waitlist.manage": "waitlist.manage",
  "waitlist.invite": "members.invite",
  "flags.manage": "flags.manage",
  "workflows.read": "workflow.read",
  "workflows.run": "workflow.run",
  "workflows.admin": "workflow.admin",
  "workflow-builder.read": "workflow.read",
  "workflow-builder.run": "workflow.run",
  "workflow-builder.edit": "workflow.edit",
  "workflow-builder.publish": "workflow.publish",
  "workflow-builder.admin": "workflow.admin",
  "inbox.read": "inbox.read",
  "inbox.reply": "inbox.reply",
  "inbox.assign": "inbox.assign",
  "inbox.manage": "inbox.manage",
  "ai-chat.read": "ai_chat.read",
  "ai-chat.create": "ai_chat.create",
  "ai-chat.share": "ai_chat.share",
  "ai-chat.moderate": "ai_chat.moderate",
  "ai-chat.admin": "ai_chat.admin",
  "ai-files.upload": "ai.create",
  "ai-files.manage": "ai.admin",
  "knowledge.read": "ai.read",
  "knowledge.write": "ai.create",
  "knowledge.manage": "ai.admin",
  "memory.read": "ai.read",
  "memory.manage": "ai.admin",
  "agents.read": "ai.read",
  "agents.create": "ai.create",
  "agents.publish": "ai.share",
  "agents.moderate": "ai.moderate",
  "connectors.read": "ai.read",
  "connectors.use": "ai.create",
  "connectors.manage": "ai.admin",
  "ai-tasks.create": "ai.create",
  "ai-tasks.manage": "ai.admin",
  "ai-providers.use": "ai.create",
  "ai-providers.manage": "ai.admin",
  "number-sequences.assign": "number_sequences.assign",
  "teams.manage": "teams.manage",
  "teams.read": "teams.read",
  "tags.manage": "tags.manage",
  "tags.read": "tags.read",
  "tags.apply": "tags.apply",
  "catalog.manage": "catalog.manage",
  "catalog.read": "catalog.read",
  "inventory.manage": "inventory.manage",
  "inventory.read": "inventory.read",
  "inventory.reserve": "inventory.reserve",
  "inventory.purchase": "inventory.purchase",
  "orders.manage": "orders.manage",
  "orders.read": "orders.read",
  "promotions.manage": "promotions.manage",
  "promotions.read": "promotions.read",
  "custom-fields.manage": "custom_fields.manage",
  "custom-fields.read": "custom_fields.read",
  "custom-fields.sensitive": "custom_fields.sensitive.read",
  "share-links.create": "share_links.create",
  "share-links.read": "share_links.read",
  "reminders.manage": "reminders.manage",
  "reminders.read": "reminders.read",
  "imports.manage": "imports.manage",
  "saved-views.read": "views.read",
  "saved-views.share": "views.share",
  "relations.read": "relations.read",
  "relations.manage": "relations.manage",
  "bulk.run": "bulk.run",
  "search.read": "search.read",
  "metrics.read": "metrics.read",
  "metrics.manage": "metrics.manage",
  "calendar.manage": "calendar.manage",
  "calendar.write": "calendar.write",
  "calendar.read": "calendar.read",
  "bookings.manage": "bookings.manage",
  "bookings.create": "bookings.create",
  "bookings.read": "bookings.read",
  "versions.read": "versions.read",
  "versions.create": "versions.create",
  "versions.restore": "versions.restore",
  "versions.manage": "versions.manage",
  "trash.read": "trash.read",
  "trash.create": "trash.create",
  "trash.restore": "trash.restore",
  "trash.manage": "trash.manage",
  "reactions.read": "reactions.read",
  "reactions.create": "reactions.create",
  "reactions.manage": "reactions.manage",
  "approvals.read": "approvals.read",
  "approvals.request": "approvals.request",
  "approvals.manage": "approvals.manage",
  "access-requests.read": "access_requests.read",
  "access-requests.create": "access_requests.create",
  "access-requests.manage": "access_requests.manage",
  "documents.read": "documents.read",
  "documents.write": "documents.write",
  "documents.manage": "documents.manage",
  "drive.read": "drive.read",
  "drive.create": "drive.create",
  "drive.manage": "drive.manage",
  "forms.read": "forms.read",
  "forms.manage": "forms.manage",
  "forms.submit": "forms.submit",
  "forms.review": "forms.review",
  "signatures.read": "signatures.read",
  "signatures.request": "signatures.request",
  "signatures.manage": "signatures.manage",
  "templates.read": "templates.read",
  "templates.apply": "templates.apply",
  "templates.manage": "templates.manage",
  "time-tracking.read": "time_tracking.read",
  "time-tracking.track": "time_tracking.track",
  "time-tracking.approve": "time_tracking.approve",
  "time-tracking.manage": "time_tracking.manage",
  "service-principals.read": "service_principals.read",
  "service-principals.manage": "service_principals.manage",
  "pipelines.read": "pipelines.read",
  "pipelines.manage": "pipelines.manage",
  "parties.read": "parties.read",
  "parties.write": "parties.write",
  "parties.manage": "parties.manage",
  "engagements.read": "engagements.read",
  "engagements.write": "engagements.write",
  "engagements.manage": "engagements.manage",
  "deals.read": "deals.read",
  "deals.write": "deals.write",
  "deals.manage": "deals.manage",
  "work-items.read": "work_items.read",
  "work-items.write": "work_items.write",
  "work-items.manage": "work_items.manage",
  "quotes.read": "quotes.read",
  "quotes.write": "quotes.write",
  "quotes.manage": "quotes.manage",
  "invoices.read": "invoices.read",
  "invoices.write": "invoices.write",
  "invoices.manage": "invoices.manage",
  "sla.read": "sla.read",
  "sla.manage": "sla.manage",
  "targets.read": "targets.read",
  "targets.manage": "targets.manage",
  "hiring.read": "hiring.read",
  "hiring.write": "hiring.write",
  "hiring.manage": "hiring.manage",
  "employees.read": "employees.read",
  "employees.write": "employees.write",
  "employees.viewSensitive": "employees.view_sensitive",
  "collections.read": "collections.read",
  "collections.write": "collections.write",
  "collections.share": "collections.share",
  "domains.read": "domains.read",
  "domains.manage": "domains.manage",
  "rules.read": "rules.read",
  "rules.edit": "rules.edit",
  "rules.publish": "rules.publish",
  "rules.admin": "rules.admin",
  "reviews.manage": "reviews.manage",
  "leave.request": "leave.request",
  "leave.read": "leave.read",
  "leave.approve": "leave.approve",
  "leave.manage": "leave.manage",
} as const;

/** An operation name, `<module>.<action>`. */
export type Operation = keyof typeof OPERATIONS;

/** The modules with operations. */
export type OperationModule = Operation extends `${infer M}.${string}`
  ? M
  : never;

/** One module's operations by action, as `moduleOperations` returns them. */
export type ModuleOperations<M extends OperationModule> = {
  readonly [
    O in Operation as O extends `${M}.${infer A}` ? A : never
  ]: (typeof OPERATIONS)[O];
};

const operationsByModule = new Map<string, Record<string, string>>();

for (const [name, key] of Object.entries(OPERATIONS)) {
  const dot = name.indexOf(".");
  const module = name.slice(0, dot);
  const actions = operationsByModule.get(module) ?? {};
  actions[name.slice(dot + 1)] = key;
  operationsByModule.set(module, actions);
}

/** `module`'s default keys by action, from `OPERATIONS`. */
export function moduleOperations<M extends OperationModule>(
  module: M,
): ModuleOperations<M> {
  // SAFETY: built from OPERATIONS above, which holds every action of M.
  return (operationsByModule.get(module) ?? {}) as ModuleOperations<M>;
}

/** Whether `name` is a module with actions in `OPERATIONS`. */
export const isOperationModule = (name: string): name is OperationModule =>
  operationsByModule.has(name);

/**
 * Where each module action checks its key: `tenant` through `member_can`, `can`
 * or `tenant_ids_with` (a provider's `idsWith`), and `platform` through
 * `is_platform` or `platform_can` (a provider's `isPlatform`).
 */
export const MODULE_PERMISSION_SCOPES: {
  readonly [M in OperationModule]: {
    readonly [A in keyof ModuleOperations<M>]: "tenant" | "platform";
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
  audit: { view: "tenant", viewAll: "platform", revert: "tenant" },
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
  "data-lifecycle": {
    export: "tenant",
    delete: "tenant",
    cancelDelete: "tenant",
  },
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
  "number-sequences": { assign: "tenant" },
  teams: { manage: "tenant", read: "tenant" },
  tags: { manage: "tenant", read: "tenant", apply: "tenant" },
  catalog: { manage: "tenant", read: "tenant" },
  inventory: {
    manage: "tenant",
    read: "tenant",
    reserve: "tenant",
    purchase: "tenant",
  },
  orders: { manage: "tenant", read: "tenant" },
  promotions: { manage: "tenant", read: "tenant" },
  "custom-fields": { manage: "tenant", read: "tenant", sensitive: "tenant" },
  "share-links": { create: "tenant", read: "tenant" },
  reminders: { manage: "tenant", read: "tenant" },
  imports: { manage: "tenant" },
  "saved-views": { read: "tenant", share: "tenant" },
  relations: { read: "tenant", manage: "tenant" },
  bulk: { run: "tenant" },
  search: { read: "tenant" },
  metrics: { read: "tenant", manage: "tenant" },
  calendar: { manage: "tenant", write: "tenant", read: "tenant" },
  bookings: { manage: "tenant", create: "tenant", read: "tenant" },
  versions: {
    read: "tenant",
    create: "tenant",
    restore: "tenant",
    manage: "tenant",
  },
  trash: {
    read: "tenant",
    create: "tenant",
    restore: "tenant",
    manage: "tenant",
  },
  reactions: { read: "tenant", create: "tenant", manage: "tenant" },
  approvals: { read: "tenant", request: "tenant", manage: "tenant" },
  "access-requests": { read: "tenant", create: "tenant", manage: "tenant" },
  documents: { read: "tenant", write: "tenant", manage: "tenant" },
  drive: { read: "tenant", create: "tenant", manage: "tenant" },
  forms: {
    read: "tenant",
    manage: "tenant",
    submit: "tenant",
    review: "tenant",
  },
  signatures: { read: "tenant", request: "tenant", manage: "tenant" },
  templates: { read: "tenant", apply: "tenant", manage: "tenant" },
  "time-tracking": {
    read: "tenant",
    track: "tenant",
    approve: "tenant",
    manage: "tenant",
  },
  "service-principals": { read: "tenant", manage: "tenant" },
  pipelines: { read: "tenant", manage: "tenant" },
  parties: { read: "tenant", write: "tenant", manage: "tenant" },
  engagements: { read: "tenant", write: "tenant", manage: "tenant" },
  deals: { read: "tenant", write: "tenant", manage: "tenant" },
  "work-items": { read: "tenant", write: "tenant", manage: "tenant" },
  quotes: { read: "tenant", write: "tenant", manage: "tenant" },
  invoices: { read: "tenant", write: "tenant", manage: "tenant" },
  sla: { read: "tenant", manage: "tenant" },
  targets: { read: "tenant", manage: "tenant" },
  hiring: { read: "tenant", write: "tenant", manage: "tenant" },
  employees: { read: "tenant", write: "tenant", viewSensitive: "tenant" },
  collections: { read: "tenant", write: "tenant", share: "tenant" },
  domains: { read: "tenant", manage: "tenant" },
  rules: { read: "tenant", edit: "tenant", publish: "tenant", admin: "tenant" },
  reviews: { manage: "tenant" },
  leave: {
    request: "tenant",
    read: "tenant",
    approve: "tenant",
    manage: "tenant",
  },
};

export function accessModel(ctx: ModuleContext): AccessModel {
  return ctx.modules.access?.model ?? "roles";
}

/**
 * `blocks.access.roles`, or the default roles with their keys renamed after the
 * blocks' entities (`work_items.*` becomes `tasks.*`).
 */
export function rolesOf(
  ctx: ModuleContext,
): Readonly<Record<string, readonly string[]>> {
  const configured = ctx.modules.access?.roles;

  if (configured !== undefined) {
    return configured;
  }

  const naming = ctx.blockNaming();

  return naming.renamed
    ? Object.fromEntries(
        Object.entries(DEFAULT_ROLES).map(([role, keys]) => [
          role,
          keys.map((key) => naming.rename(key)),
        ]),
      )
    : DEFAULT_ROLES;
}

export const roleNames = (ctx: ModuleContext): readonly string[] =>
  Object.keys(rolesOf(ctx));

/**
 * The scope name tenants use in `can(scope, id, permission)`
 * (`blocks.access.options.scope`, default `organization`). `tenant` is accepted
 * too.
 */
export const tenantScope = (ctx: ModuleContext): string =>
  ctx.of("access").text("scope", "organization");

/**
 * `blocks.invitations.options.platformRoles` under the `provider` model: the
 * app's table of platform role assignments, so platform invitations insert into
 * it.
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
  /**
   * A SQL template with `{user}` and `{role}` (the role name) deciding who
   * assigns which platform role.
   */
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

  if (value === undefined) {
    return undefined;
  }

  const where = "blocks.invitations.options.platformRoles";

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
  if (providerPlatformRoles(ctx)) {
    return true;
  }

  return (
    accessModel(ctx) === "catalog" &&
    ctx.of("access").hasTable("platformAssignments")
  );
}

/**
 * Whether catalog role row `alias` is a tenant or a platform role, or
 * `undefined` when roles carry no scope. Managed catalogs have a `scope`
 * column; an adopted one maps `roles.scope` and names its values in
 * `blocks.access.options.tenantRoleScope` and `platformRoleScope`.
 */
export function roleScopeIs(
  ctx: ModuleContext,
  alias: string,
  scope: "tenant" | "platform",
): string | undefined {
  if (accessModel(ctx) !== "catalog") {
    return undefined;
  }

  const access = ctx.of("access");

  if (
    !access.manages &&
    typeof access.config.columns["roles"]?.["scope"] !== "string"
  ) {
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

  if (shorthand === undefined) {
    return ctx.permissionKey(action, fallback);
  }

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
