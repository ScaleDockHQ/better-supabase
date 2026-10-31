import type { AccessBlockConfig } from "../../config/blocks.ts";
import type { BlockSqlContext } from "../context.ts";

import { currentPermissionKeys } from "../../core/renames.ts";
import { sqlString } from "../../core/template.ts";

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
    "timeline.read",
    "attachments.*",
    "data_lifecycle.export",
    "onboarding.*",
    "inbox.*",
    "ai_chat.*",
    "agents.*",
    "ai_files.*",
    "ai_keys.*",
    "ai_schedules.*",
    "connectors.*",
    "knowledge.*",
    "memory.*",
    "tags.*",
    "teams.*",
    "subjects.*",
    "custom_fields.*",
    "share_links.*",
    "reminders.*",
    "imports.*",
    "saved_views.*",
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
    "service_accounts.*",
    "pipelines.*",
    "contacts.*",
    "activities.*",
    "deals.*",
    "tasks.*",
    "quotes.*",
    "invoices.*",
    "sla.*",
    "goals.*",
    "hiring.*",
    "employees.*",
    "collections.*",
    "messages.*",
    "channels.*",
    "mail_sync.*",
    "legal_entities.*",
    "segments.*",
    "assignment.*",
    "enrichment.*",
    "forecasts.*",
    "field_history.*",
    "domains.*",
    "automations.*",
    "reviews.*",
    "leave.*",
    "ledger.*",
    "assets.*",
    "scores.*",
    "moderation.*",
    "enrollments.*",
    "guests.*",
    "passes.*",
    "billable_time.*",
    "leases.*",
    "expenses.*",
    "donations.*",
    "dispatch.*",
    "shipments.*",
    "contracts.*",
    "compliance.*",
    "acknowledgements.*",
    "incidents.*",
    "courses.*",
    "sequences.*",
    "posts.*",
    "content.*",
    "qualifications.*",
    "risks.*",
    "shifts.*",
    "consents.*",
    "waitlist.invite",
    "accounting.*",
    "observations.*",
    "medications.*",
    "care_plans.*",
    "cases.*",
    "inspections.*",
    "meetings.*",
    "maintenance.*",
    "dam.*",
    "manufacturing.*",
    "banking.*",
    "tax.*",
    "funding.*",
    "payroll_export.*",
  ],
  member: [
    "organization.read",
    "members.read",
    "notifications.read",
    "api_keys.own",
    "settings.read",
    "timeline.read",
    "attachments.read",
    "attachments.upload",
    "onboarding.read",
    "inbox.read",
    "inbox.reply",
    "ai_chat.read",
    "ai_chat.create",
    "ai_chat.share",
    "agents.read",
    "agents.write",
    "agents.publish",
    "ai_files.upload",
    "ai_keys.use",
    "ai_schedules.write",
    "connectors.read",
    "connectors.use",
    "knowledge.read",
    "knowledge.write",
    "memory.read",
    "custom_fields.read",
    "teams.read",
    "tags.read",
    "tags.apply",
    "share_links.read",
    "reminders.read",
    "saved_views.read",
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
    "documents.suggest",
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
    "contacts.read",
    "contacts.write",
    "activities.read",
    "activities.write",
    "deals.read",
    "deals.write",
    "tasks.read",
    "tasks.write",
    "quotes.read",
    "quotes.write",
    "invoices.read",
    "sla.read",
    "goals.read",
    "employees.read",
    "collections.read",
    "collections.write",
    "domains.read",
    "automations.read",
    "assets.read",
    "scores.read",
    "moderation.report",
    "enrollments.read",
    "leases.maintain",
    "expenses.submit",
    "dispatch.read",
    "dispatch.work",
    "shipments.read",
    "contracts.read",
    "contracts.write",
    "compliance.read",
    "compliance.collect",
    "acknowledgements.acknowledge",
    "incidents.read",
    "incidents.write",
    "courses.read",
    "sequences.read",
    "sequences.enroll",
    "posts.read",
    "posts.write",
    "content.read",
    "content.write",
    "shifts.read",
    "shifts.request",
    "messages.read",
    "messages.send",
    "channels.create",
    "mail_sync.read",
    "legal_entities.read",
    "mail_sync.connect",
    "mail_sync.send",
    "segments.read",
    "assignment.read",
    "enrichment.read",
    "forecasts.read",
    "field_history.read",
    "risks.read",
    "observations.read",
    "observations.record",
    "care_plans.read",
    "cases.read",
    "cases.create",
    "manufacturing.read",
    "manufacturing.produce",
    "banking.read",
    "banking.reconcile",
    "tax.read",
    "funding.read",
    "funding.register",
  ],
  viewer: ["organization.read"],
};

/**
 * The permission key each operation checks by default, keyed
 * `<module>.<action>`. `blocks.<name>.permissions` renames a key per module,
 * `authorization.operations` overrides it for a provider, and the access
 * module's `operation_permission(op)` answers the result in SQL. Keys are
 * `<area>.<verb>` (ADR 0130): the area is the block name in snake_case; the
 * verb is `read`, `write`, `delete`, `manage` or a domain verb, never `view`,
 * `edit` or `admin`. `messaging`, `comments` and `channels` share `messages.*`;
 * `organizations` owns `organization.*`, `members.*` and `platform.*` (or a key
 * `is_platform()` checks). Renamed keys go in `PERMISSION_KEY_RENAMES`
 * (`src/core/renames.ts`) for one minor.
 */
export const OPERATIONS = {
  "organizations.update": "organization.update",
  "organizations.delete": "organization.delete",
  "organizations.listMembers": "members.read",
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
  "impersonation.start": "impersonation.start",
  "impersonation.view": "impersonation.read",
  "impersonation.revoke": "impersonation.revoke",
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
  "comments.read": "messages.read",
  "comments.create": "messages.send",
  "comments.moderate": "messages.moderate",
  "timeline.read": "timeline.read",
  "data-lifecycle.export": "data_lifecycle.export",
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
  "waitlist.invite": "waitlist.invite",
  "flags.manage": "flags.manage",
  "workflows.read": "workflows.read",
  "workflows.run": "workflows.run",
  "workflows.admin": "workflows.manage",
  "workflow-editor.read": "workflow_editor.read",
  "workflow-editor.run": "workflow_editor.run",
  "workflow-editor.edit": "workflow_editor.write",
  "workflow-editor.publish": "workflow_editor.publish",
  "workflow-editor.admin": "workflow_editor.manage",
  "inbox.read": "inbox.read",
  "inbox.reply": "inbox.reply",
  "inbox.assign": "inbox.assign",
  "inbox.manage": "inbox.manage",
  "ai-chat.read": "ai_chat.read",
  "ai-chat.create": "ai_chat.create",
  "ai-chat.share": "ai_chat.share",
  "ai-chat.moderate": "ai_chat.moderate",
  "ai-chat.admin": "ai_chat.manage",
  "ai-files.upload": "ai_files.upload",
  "ai-files.manage": "ai_files.manage",
  "knowledge.read": "knowledge.read",
  "knowledge.write": "knowledge.write",
  "knowledge.manage": "knowledge.manage",
  "memory.read": "memory.read",
  "memory.manage": "memory.manage",
  "agents.read": "agents.read",
  "agents.create": "agents.write",
  "agents.publish": "agents.publish",
  "agents.moderate": "agents.moderate",
  "connectors.read": "connectors.read",
  "connectors.use": "connectors.use",
  "connectors.manage": "connectors.manage",
  "ai-schedules.create": "ai_schedules.write",
  "ai-schedules.manage": "ai_schedules.manage",
  "ai-keys.use": "ai_keys.use",
  "ai-keys.manage": "ai_keys.manage",
  "numbering.assign": "numbering.assign",
  "teams.manage": "teams.manage",
  "teams.read": "teams.read",
  "subjects.manage": "subjects.manage",
  "permissions.listRoles": "members.read",
  "permissions.setOverride": "roles.manage",
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
  "orders.prepare": "orders.prepare",
  "orders.overrideCredit": "orders.override_credit",
  "promotions.manage": "promotions.manage",
  "promotions.read": "promotions.read",
  "custom-fields.manage": "custom_fields.manage",
  "custom-fields.read": "custom_fields.read",
  "custom-fields.sensitive": "custom_fields.read_sensitive",
  "share-links.create": "share_links.create",
  "share-links.read": "share_links.read",
  "reminders.manage": "reminders.manage",
  "reminders.read": "reminders.read",
  "imports.manage": "imports.manage",
  "saved-views.read": "saved_views.read",
  "saved-views.share": "saved_views.share",
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
  "access-requests.emergency": "access_requests.emergency",
  "access-requests.review": "access_requests.review",
  "documents.read": "documents.read",
  "documents.write": "documents.write",
  "documents.suggest": "documents.suggest",
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
  "service-accounts.read": "service_accounts.read",
  "service-accounts.manage": "service_accounts.manage",
  "pipelines.read": "pipelines.read",
  "pipelines.manage": "pipelines.manage",
  "contacts.read": "contacts.read",
  "contacts.write": "contacts.write",
  "contacts.manage": "contacts.manage",
  "contacts.approveSupplier": "contacts.approve_supplier",
  "activities.read": "activities.read",
  "activities.write": "activities.write",
  "activities.manage": "activities.manage",
  "activities.readRestricted": "activities.read_restricted",
  "deals.read": "deals.read",
  "deals.write": "deals.write",
  "deals.manage": "deals.manage",
  "tasks.read": "tasks.read",
  "tasks.write": "tasks.write",
  "tasks.manage": "tasks.manage",
  "quotes.read": "quotes.read",
  "quotes.write": "quotes.write",
  "quotes.manage": "quotes.manage",
  "invoices.read": "invoices.read",
  "invoices.write": "invoices.write",
  "invoices.manage": "invoices.manage",
  "invoices.purchase": "invoices.purchase",
  "invoices.overrideMatch": "invoices.override_match",
  "invoices.collect": "invoices.collect",
  "sla.read": "sla.read",
  "sla.manage": "sla.manage",
  "goals.read": "goals.read",
  "goals.manage": "goals.manage",
  "hiring.read": "hiring.read",
  "hiring.write": "hiring.write",
  "hiring.manage": "hiring.manage",
  "employees.read": "employees.read",
  "employees.write": "employees.write",
  "employees.viewSensitive": "employees.read_sensitive",
  "collections.read": "collections.read",
  "collections.write": "collections.write",
  "collections.share": "collections.share",
  "domains.read": "domains.read",
  "domains.manage": "domains.manage",
  "automations.read": "automations.read",
  "automations.edit": "automations.write",
  "automations.publish": "automations.publish",
  "automations.admin": "automations.manage",
  "reviews.manage": "reviews.manage",
  "leave.request": "leave.request",
  "leave.read": "leave.read",
  "leave.approve": "leave.approve",
  "leave.manage": "leave.manage",
  "ledger.read": "ledger.read",
  "ledger.manage": "ledger.manage",
  "ledger.post": "ledger.post",
  "assets.read": "assets.read",
  "assets.manage": "assets.manage",
  "assets.assign": "assets.assign",
  "scores.read": "scores.read",
  "scores.manage": "scores.manage",
  "scores.compute": "scores.compute",
  "moderation.read": "moderation.read",
  "moderation.report": "moderation.report",
  "moderation.manage": "moderation.manage",
  "moderation.ban": "moderation.ban",
  "enrollments.read": "enrollments.read",
  "enrollments.enroll": "enrollments.enroll",
  "enrollments.manage": "enrollments.manage",
  "guests.read": "guests.read",
  "guests.manage": "guests.manage",
  "passes.read": "passes.read",
  "passes.manage": "passes.manage",
  "passes.checkIn": "passes.check_in",
  "billable-time.read": "billable_time.read",
  "billable-time.manage": "billable_time.manage",
  "billable-time.invoice": "billable_time.invoice",
  "leases.read": "leases.read",
  "leases.manage": "leases.manage",
  "leases.maintain": "leases.maintain",
  "expenses.read": "expenses.read",
  "expenses.submit": "expenses.submit",
  "expenses.approve": "expenses.approve",
  "expenses.manage": "expenses.manage",
  "donations.read": "donations.read",
  "donations.manage": "donations.manage",
  "dispatch.read": "dispatch.read",
  "dispatch.manage": "dispatch.manage",
  "dispatch.work": "dispatch.work",
  "shipments.read": "shipments.read",
  "shipments.manage": "shipments.manage",
  "contracts.read": "contracts.read",
  "contracts.write": "contracts.write",
  "contracts.manage": "contracts.manage",
  "compliance.read": "compliance.read",
  "compliance.manage": "compliance.manage",
  "compliance.collect": "compliance.collect",
  "acknowledgements.read": "acknowledgements.read",
  "acknowledgements.manage": "acknowledgements.manage",
  "acknowledgements.acknowledge": "acknowledgements.acknowledge",
  "incidents.read": "incidents.read",
  "incidents.write": "incidents.write",
  "incidents.manage": "incidents.manage",
  "courses.read": "courses.read",
  "courses.enroll": "courses.enroll",
  "courses.manage": "courses.manage",
  "sequences.read": "sequences.read",
  "sequences.enroll": "sequences.enroll",
  "sequences.manage": "sequences.manage",
  "posts.read": "posts.read",
  "posts.write": "posts.write",
  "posts.moderate": "posts.moderate",
  "posts.manage": "posts.manage",
  "content.read": "content.read",
  "content.write": "content.write",
  "content.publish": "content.publish",
  "qualifications.read": "qualifications.read",
  "qualifications.grant": "qualifications.grant",
  "qualifications.manage": "qualifications.manage",
  "shifts.read": "shifts.read",
  "shifts.write": "shifts.write",
  "shifts.request": "shifts.request",
  "shifts.manage": "shifts.manage",
  "accounting.read": "accounting.read",
  "accounting.write": "accounting.write",
  "accounting.post": "accounting.post",
  "accounting.close": "accounting.close",
  "accounting.manage": "accounting.manage",
  "consents.read": "consents.read",
  "consents.record": "consents.record",
  "consents.manage": "consents.manage",
  "medications.read": "medications.read",
  "medications.prescribe": "medications.prescribe",
  "medications.administer": "medications.administer",
  "medications.manage": "medications.manage",
  "funding.read": "funding.read",
  "funding.write": "funding.write",
  "funding.register": "funding.register",
  "funding.approve": "funding.approve",
  "funding.claim": "funding.claim",
  "funding.manage": "funding.manage",
  "messaging.read": "messages.read",
  "messaging.send": "messages.send",
  "messaging.moderate": "messages.moderate",
  "channels.read": "messages.read",
  "channels.create": "channels.create",
  "channels.manage": "channels.manage",
  "mail-sync.read": "mail_sync.read",
  "mail-sync.connect": "mail_sync.connect",
  "mail-sync.send": "mail_sync.send",
  "mail-sync.manage": "mail_sync.manage",
  "legal-entities.read": "legal_entities.read",
  "legal-entities.manage": "legal_entities.manage",
  "segments.read": "segments.read",
  "segments.edit": "segments.write",
  "assignment.read": "assignment.read",
  "assignment.manage": "assignment.manage",
  "assignment.assign": "assignment.assign",
  "enrichment.read": "enrichment.read",
  "enrichment.run": "enrichment.run",
  "forecasts.read": "forecasts.read",
  "forecasts.snapshot": "forecasts.snapshot",
  "field-history.read": "field_history.read",
  "risks.read": "risks.read",
  "risks.write": "risks.write",
  "risks.assess": "risks.assess",
  "risks.manage": "risks.manage",
  "observations.read": "observations.read",
  "observations.record": "observations.record",
  "observations.manage": "observations.manage",
  "care-plans.read": "care_plans.read",
  "care-plans.write": "care_plans.write",
  "care-plans.evaluate": "care_plans.evaluate",
  "care-plans.publish": "care_plans.publish",
  "care-plans.manage": "care_plans.manage",
  "cases.read": "cases.read",
  "cases.create": "cases.create",
  "cases.write": "cases.write",
  "cases.close": "cases.close",
  "cases.manage": "cases.manage",
  "inspections.read": "inspections.read",
  "inspections.write": "inspections.write",
  "inspections.manage": "inspections.manage",
  "meetings.read": "meetings.read",
  "meetings.write": "meetings.write",
  "meetings.manage": "meetings.manage",
  "dam.read": "dam.read",
  "dam.write": "dam.write",
  "maintenance.read": "maintenance.read",
  "maintenance.record": "maintenance.record",
  "maintenance.manage": "maintenance.manage",
  "manufacturing.read": "manufacturing.read",
  "manufacturing.write": "manufacturing.write",
  "manufacturing.produce": "manufacturing.produce",
  "manufacturing.manage": "manufacturing.manage",
  "banking.read": "banking.read",
  "banking.import": "banking.import",
  "banking.reconcile": "banking.reconcile",
  "banking.manage": "banking.manage",
  "tax.read": "tax.read",
  "tax.manage": "tax.manage",
  "payroll-export.read": "payroll_export.read",
  "payroll-export.export": "payroll_export.export",
} as const;

/** An operation name, `<module>.<action>`. */
export type Operation = keyof typeof OPERATIONS;

/** The modules with operations. */
export type OperationModule = Operation extends `${infer M}.${string}`
  ? M
  : never;

/** One module's operations by action, as `moduleOperations` returns them. */
export type BlockSqlOperations<M extends OperationModule> = {
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
): BlockSqlOperations<M> {
  // SAFETY: built from OPERATIONS above, which holds every action of M.
  return (operationsByModule.get(module) ?? {}) as BlockSqlOperations<M>;
}

/** Whether `name` is a module with actions in `OPERATIONS`. */
export const isOperationModule = (name: string): name is OperationModule =>
  operationsByModule.has(name);

export function accessModel(ctx: BlockSqlContext): AccessModel {
  return ctx.modules.permissions?.model ?? "roles";
}

/**
 * `blocks.permissions.roles`, or the default roles with their keys renamed for
 * each block installed under another name (`tasks.*` becomes `tickets.*`). A
 * configured role that still grants a key the 0.46 convention renamed also
 * grants its new keys, until the next minor.
 */
export function rolesOf(
  ctx: BlockSqlContext,
): Readonly<Record<string, readonly string[]>> {
  const configured = ctx.modules.permissions?.roles;

  if (configured !== undefined) {
    return Object.fromEntries(
      Object.entries(configured).map(([role, keys]) => [
        role,
        [...new Set(keys.flatMap((k) => [k, ...currentPermissionKeys(k)]))],
      ]),
    );
  }

  const naming = ctx.blockNaming();
  const instances = ctx.instanceNamings().filter((each) => each.renamed);

  return naming.renamed || instances.length > 0
    ? Object.fromEntries(
        Object.entries(DEFAULT_ROLES).map(([role, keys]) => [
          role,
          [
            ...new Set(
              keys.flatMap((key) => [
                naming.rename(key),
                ...instances.map((each) => each.rename(key)),
              ]),
            ),
          ],
        ]),
      )
    : DEFAULT_ROLES;
}

export const roleNames = (ctx: BlockSqlContext): readonly string[] =>
  Object.keys(rolesOf(ctx));

/**
 * The scope name tenants use in `can(scope, id, permission)`
 * (`blocks.permissions.options.scope`, default `organization`). `tenant` is
 * accepted too.
 */
export const tenantScope = (ctx: BlockSqlContext): string =>
  ctx.of("permissions").text("scope", "organization");

/**
 * Whether catalog role row `alias` is a tenant or a platform role, or
 * `undefined` when roles carry no scope. Managed catalogs have a `scope`
 * column; an adopted one maps `roles.scope` and names its values in
 * `blocks.permissions.options.tenantRoleScope` and `platformRoleScope`.
 */
export function roleScopeIs(
  ctx: BlockSqlContext,
  alias: string,
  scope: "tenant" | "platform",
): string | undefined {
  if (accessModel(ctx) !== "catalog") {
    return undefined;
  }

  const access = ctx.of("permissions");

  if (
    !access.owns("roles") &&
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
  "webhooks-in": { create: "manage", update: "manage", delete: "manage" },
};

export function modulePermissionKey(
  ctx: BlockSqlContext,
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
  ctx: BlockSqlContext,
  action: string,
  fallback: string,
): string => sqlString(modulePermissionKey(ctx, action, fallback));
