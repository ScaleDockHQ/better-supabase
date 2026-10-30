/**
 * The names the naming convention changed (ADR 0130), old to new: permission
 * keys in 0.46; entity keys, subject types, hints and event types in 0.47. The
 * shims, the stored-name migrations, the codemods and doctor read these maps,
 * so each rename is written once.
 */

/**
 * The `better-supabase codemod` version that applies the permission key
 * renames.
 */
export const RENAMES_CODEMOD = "0.46";

/**
 * The codemod that applies the 0.47 entity, subject type, hint and event type
 * renames.
 */
export const ENTITY_RENAMES_CODEMOD = "0.47";

export { HINT_RENAMES, legacyHintOf } from "./hint-renames.ts";

const frozen = (
  entries: Readonly<Record<string, string>>,
): Readonly<Record<string, string>> => Object.freeze({ ...entries });

/**
 * Permission keys whose area is now the block name, or whose verb follows the
 * convention (`read`, `write`, `manage`). Wildcards are listed too.
 */
export const PERMISSION_KEY_RENAMES: Readonly<Record<string, string>> = frozen({
  "activity.*": "timeline.*",
  "activity.read": "timeline.read",
  "ai_chat.admin": "ai_chat.manage",
  "controls.*": "compliance.*",
  "controls.acknowledge": "compliance.acknowledge",
  "controls.collect": "compliance.collect",
  "controls.manage": "compliance.manage",
  "controls.read": "compliance.read",
  "custom_fields.sensitive.read": "custom_fields.read_sensitive",
  "employees.view_sensitive": "employees.read_sensitive",
  "engagements.*": "activities.*",
  "engagements.manage": "activities.manage",
  "engagements.read": "activities.read",
  "engagements.write": "activities.write",
  "history.*": "field_history.*",
  "history.read": "field_history.read",
  "mail.*": "mail_sync.*",
  "mail.connect": "mail_sync.connect",
  "mail.manage": "mail_sync.manage",
  "mail.read": "mail_sync.read",
  "mail.send": "mail_sync.send",
  "number_sequences.*": "numbering.*",
  "number_sequences.assign": "numbering.assign",
  "organization.export": "data_lifecycle.export",
  "parties.*": "contacts.*",
  "parties.manage": "contacts.manage",
  "parties.read": "contacts.read",
  "parties.write": "contacts.write",
  "rules.*": "automations.*",
  "rules.admin": "automations.manage",
  "rules.edit": "automations.write",
  "rules.publish": "automations.publish",
  "rules.read": "automations.read",
  "segments.edit": "segments.write",
  "service_principals.*": "service_accounts.*",
  "service_principals.manage": "service_accounts.manage",
  "service_principals.read": "service_accounts.read",
  "support.*": "impersonation.*",
  "support.read": "impersonation.read",
  "support.revoke": "impersonation.revoke",
  "support.start": "impersonation.start",
  "targets.*": "goals.*",
  "targets.manage": "goals.manage",
  "targets.read": "goals.read",
  "views.*": "saved_views.*",
  "views.read": "saved_views.read",
  "views.share": "saved_views.share",
  "work_items.*": "tasks.*",
  "work_items.manage": "tasks.manage",
  "work_items.read": "tasks.read",
  "work_items.write": "tasks.write",
  "workflow.*": "workflows.*",
  "workflow.admin": "workflows.manage",
  "workflow.edit": "workflow_editor.write",
  "workflow.publish": "workflow_editor.publish",
  "workflow.read": "workflows.read",
  "workflow.run": "workflows.run",
});

/**
 * Keys one old key granted in several blocks: the `ai.*` keys of the AI blocks,
 * the `workflow.*` keys `workflow-editor` shared with `workflows`, and the keys
 * `waitlist` and `data-lifecycle` borrowed from `organizations`. A role that
 * held the old key gets every key listed, on top of its rename in
 * `PERMISSION_KEY_RENAMES`.
 */
export const PERMISSION_KEY_SPLITS: Readonly<
  Record<string, readonly string[]>
> = Object.freeze({
  "ai.*": [
    "agents.*",
    "ai_files.*",
    "ai_keys.*",
    "ai_schedules.*",
    "connectors.*",
    "knowledge.*",
    "memory.*",
  ],
  "ai.admin": [
    "ai_files.manage",
    "ai_keys.manage",
    "ai_schedules.manage",
    "connectors.manage",
    "knowledge.manage",
    "memory.manage",
  ],
  "ai.create": [
    "agents.write",
    "ai_files.upload",
    "ai_keys.use",
    "ai_schedules.write",
    "connectors.use",
    "knowledge.write",
  ],
  "ai.moderate": ["agents.moderate"],
  "ai.read": [
    "agents.read",
    "connectors.read",
    "knowledge.read",
    "memory.read",
  ],
  "ai.share": ["agents.publish"],
  "members.*": ["waitlist.invite"],
  "members.invite": ["waitlist.invite"],
  "organization.*": ["data_lifecycle.*"],
  "workflow.*": ["workflow_editor.*"],
  "workflow.admin": ["workflow_editor.manage"],
  "workflow.read": ["workflow_editor.read"],
  "workflow.run": ["workflow_editor.run"],
});

/**
 * Outbox event types, old to new: the prefix is the entity's singular and the
 * verb follows the lifecycle list (`deleted`, not `removed`; `<attr>_changed`,
 * not `<attr>_set`). Wildcards whose whole prefix moved are listed too.
 */
export const EVENT_TYPE_RENAMES: Readonly<Record<string, string>> =
  /* @__PURE__ */ frozen({
    "access.*": "access_request.*",
    "access.ended": "access_request.ended",
    "access.request_approved": "access_request.approved",
    "access.requested": "access_request.requested",
    "ai_tool_policy.set": "ai_tool_policy.updated",
    "approval_policy.removed": "approval_policy.deleted",
    "credential.set": "credential.updated",
    "custom_field.*": "field_definition.*",
    "custom_field.deleted": "field_definition.deleted",
    "drive.node_created": "drive_node.created",
    "drive.node_document_saved": "drive_node.document_saved",
    "drive.node_download_blocked_changed":
      "drive_node.download_blocked_changed",
    "drive.node_hold_placed": "drive_node.hold_placed",
    "drive.node_hold_released": "drive_node.hold_released",
    "drive.node_locked": "drive_node.locked",
    "drive.node_moved": "drive_node.moved",
    "drive.node_obsoleted": "drive_node.obsoleted",
    "drive.node_ownership_transferred": "drive_node.ownership_transferred",
    "drive.node_purged": "drive_node.purged",
    "drive.node_released": "drive_node.released",
    "drive.node_renamed": "drive_node.renamed",
    "drive.node_review_requested": "drive_node.review_requested",
    "drive.node_reviewed": "drive_node.reviewed",
    "drive.node_shared": "drive_node.shared",
    "drive.node_submitted": "drive_node.submitted",
    "drive.node_unlocked": "drive_node.unlocked",
    "drive.node_unshared": "drive_node.unshared",
    "engagement.*": "activity.*",
    "engagement.amended": "activity.amended",
    "engagement.completed": "activity.completed",
    "engagement.deleted": "activity.deleted",
    "engagement.error_marked": "activity.error_marked",
    "engagement.logged": "activity.logged",
    "engagement.recorded": "activity.recorded",
    "engagement.summarized": "activity.summarized",
    "engagement.transcribed": "activity.transcribed",
    "engagement.updated": "activity.updated",
    "flag.override_set": "flag.override_changed",
    "forecast.*": "forecast_snapshot.*",
    "forecast.snapshotted": "forecast_snapshot.created",
    "hostname.primary_set": "hostname.primary_changed",
    "hostname.removed": "hostname.deleted",
    "incoming_webhook.enabled_set": "incoming_webhook.enabled_changed",
    "job.*": "job_opening.*",
    "job.closed": "job_opening.closed",
    "job.opened": "job_opening.opened",
    "leave.adjusted": "leave_balance.adjusted",
    "leave.approved": "leave_request.approved",
    "leave.cancelled": "leave_request.cancelled",
    "leave.rejected": "leave_request.rejected",
    "leave.requested": "leave_request.requested",
    "leave.split": "leave_request.split",
    "leave.updated": "leave_request.updated",
    "marketplace_installation.removed": "marketplace_installation.deleted",
    "marketplace_invoice.state_changed": "marketplace_invoice.status_changed",
    "obligation.*": "contract_obligation.*",
    "obligation.status_changed": "contract_obligation.status_changed",
    "organization.domain_added": "sso_domain.created",
    "organization.domain_removed": "sso_domain.deleted",
    "organization.domain_updated": "sso_domain.updated",
    "organization.domain_verified": "sso_domain.verified",
    "policy.*": "compliance_policy.*",
    "policy.acknowledged": "compliance_policy.acknowledged",
    "policy.published": "compliance_policy.published",
    "postmortem.*": "incident_postmortem.*",
    "postmortem.published": "incident_postmortem.published",
    "rule.*": "automation.*",
    "rule.disabled": "automation.disabled",
    "rule.enabled": "automation.enabled",
    "rule.matched": "automation.matched",
    "rule.removed": "automation.deleted",
    "segment.removed": "segment.deleted",
    "signature.*": "signature_request.*",
    "signature.cancelled": "signature_request.cancelled",
    "signature.completed": "signature_request.completed",
    "signature.declined": "signature_request.declined",
    "signature.requested": "signature_request.requested",
    "signature.signed": "signature_request.signed",
    "support.*": "support_session.*",
    "support.denied": "support_session.denied",
    "support.ended": "support_session.ended",
    "support.started": "support_session.started",
    "time.*": "time_entry.*",
    "time.invoiced": "time_entry.invoiced",
    "variant.*": "product_variant.*",
    "variant.created": "product_variant.created",
    "variant.deleted": "product_variant.deleted",
    "variant.updated": "product_variant.updated",
    "waitlist.*": "waitlist_entry.*",
    "waitlist.approved": "waitlist_entry.approved",
    "waitlist.rejected": "waitlist_entry.rejected",
    "webhook.*": "webhook_endpoint.*",
    "webhook.delivered": "webhook_endpoint.delivered",
    "webhook.disabled": "webhook_endpoint.disabled",
    "webhook.failed": "webhook_endpoint.failed",
    "webhook.secret_rotated": "webhook_endpoint.secret_rotated",
    "work_item.*": "task.*",
    "work_item.archived": "task.archived",
    "work_item.assigned": "task.assigned",
    "work_item.closed": "task.closed",
    "work_item.created": "task.created",
    "work_item.deleted": "task.deleted",
    "work_item.reopened": "task.reopened",
    "work_item.updated": "task.updated",
    "workflow.*": "workflow_definition.*",
    "workflow.published": "workflow_definition.published",
  });

const lifecycle = (entity: string): readonly string[] => [
  `${entity}.created`,
  `${entity}.updated`,
];

/**
 * Event types that became several: a `saved` or `upserted` event is now
 * `created` or `updated`, `party.enriched` is `company.enriched` or
 * `person.enriched`, and a wildcard whose prefix only partly moved gains the
 * new prefix. A subscriber to the old type gets every type listed.
 */
export const EVENT_TYPE_SPLITS: Readonly<Record<string, readonly string[]>> =
  /* @__PURE__ */ Object.freeze({
    "agent.saved": lifecycle("agent"),
    "ai_provider_key.saved": lifecycle("ai_provider_key"),
    "announcement.saved": lifecycle("announcement"),
    "approval_policy.saved": lifecycle("approval_policy"),
    "connector.saved": lifecycle("connector"),
    "control.saved": lifecycle("control"),
    "course.saved": lifecycle("course"),
    "custom_field.saved": lifecycle("field_definition"),
    "drive.*": ["drive_node.*"],
    "enrollment_program.saved": lifecycle("enrollment_program"),
    "flag.saved": lifecycle("flag"),
    "leave.*": ["leave_request.*", "leave_balance.*"],
    "marketplace_installation.upserted": lifecycle("marketplace_installation"),
    "obligation.saved": lifecycle("contract_obligation"),
    "organization.*": ["sso_domain.*"],
    "party.*": ["company.enriched", "person.enriched"],
    "party.enriched": ["company.enriched", "person.enriched"],
    "pipeline_stage.saved": lifecycle("pipeline_stage"),
    "post_board.saved": lifecycle("post_board"),
    "rule.saved": lifecycle("automation"),
    "saved_view.saved": lifecycle("saved_view"),
    "scim_group.saved": lifecycle("scim_group"),
    "scim_user.saved": lifecycle("scim_user"),
    "score_model.saved": lifecycle("score_model"),
    "segment.saved": lifecycle("segment"),
    "sequence.saved": lifecycle("sequence"),
  });

/**
 * Subject types stored in `subject_type` columns, old to new: the subject
 * entities whose singular changed. `rename_subject_type` moves stored rows, and
 * the subjects functions read an old type as its new one for one minor.
 */
export const SUBJECT_TYPE_RENAMES: Readonly<Record<string, string>> = frozen({
  engagement: "activity",
  policy: "compliance_policy",
  work_item: "task",
});

/**
 * `blocks.<name>.entities` keys, old to new, by block. A key now equals the
 * entity's singular; an old key still resolves for one minor.
 */
export const ENTITY_KEY_RENAMES: Readonly<
  Record<string, Readonly<Record<string, string>>>
> = Object.freeze({
  "access-requests": frozen({ request: "access_request" }),
  activities: frozen({ engagement: "activity" }),
  "ai-chat": frozen({ chat: "ai_chat", project: "ai_project" }),
  "ai-files": frozen({ document: "ai_document" }),
  "ai-schedules": frozen({ task: "ai_scheduled_task" }),
  "api-keys": frozen({ key: "api_key" }),
  automations: frozen({ rule: "automation" }),
  collections: frozen({ collection: "subject_collection" }),
  compliance: frozen({ policy: "compliance_policy" }),
  connectors: frozen({ server: "connector_server" }),
  contracts: frozen({ obligation: "contract_obligation" }),
  "custom-fields": frozen({ field: "field_definition" }),
  drive: frozen({ node: "drive_node" }),
  forecasts: frozen({ snapshot: "forecast_snapshot" }),
  goals: frozen({ target: "goal" }),
  hiring: frozen({ job: "job_opening" }),
  incidents: frozen({ postmortem: "incident_postmortem" }),
  inventory: frozen({ location: "inventory_location" }),
  knowledge: frozen({ document: "knowledge_document" }),
  leave: frozen({ request: "leave_request", type: "leave_type" }),
  "saved-views": frozen({ view: "saved_view" }),
  "share-links": frozen({ link: "share_link" }),
  signatures: frozen({ request: "signature_request" }),
  sla: frozen({ policy: "sla_policy" }),
  tasks: frozen({ work_item: "task" }),
  "time-tracking": frozen({ entry: "time_entry" }),
  timeline: frozen({ entry: "timeline_entry" }),
  waitlist: frozen({ entry: "waitlist_entry" }),
  "webhooks-out": frozen({ endpoint: "webhook_endpoint" }),
  "workflow-editor": frozen({ definition: "workflow_definition" }),
});

/** `value`'s new name in `map`, or `value` when it was not renamed. */
export function renamed(
  map: Readonly<Record<string, string>>,
  value: string,
): string {
  return Object.hasOwn(map, value) ? (map[value] ?? value) : value;
}

/** Split keys that still exist: they keep their grant and add the others. */
const KEPT_SPLIT_KEYS: ReadonlySet<string> = new Set([
  "members.*",
  "members.invite",
  "organization.*",
]);

const splitsOf = (key: string): readonly string[] =>
  Object.hasOwn(PERMISSION_KEY_SPLITS, key)
    ? (PERMISSION_KEY_SPLITS[key] ?? [])
    : [];

/** Whether no block checks `key` any more: it was renamed or split up. */
export const isOldPermissionKey = (key: string): boolean =>
  Object.hasOwn(PERMISSION_KEY_RENAMES, key) ||
  (splitsOf(key).length > 0 && !KEPT_SPLIT_KEYS.has(key));

/**
 * Every key a role holding `key` holds now: its rename and the keys it was
 * split into. A key that did not change is returned as it is.
 */
export function currentPermissionKeys(key: string): readonly string[] {
  const own =
    isOldPermissionKey(key) && !Object.hasOwn(PERMISSION_KEY_RENAMES, key)
      ? []
      : [renamed(PERMISSION_KEY_RENAMES, key)];

  return [...own, ...splitsOf(key)];
}

const warned = new Set<string>();

/**
 * `currentPermissionKeys(key)`, logging an old key once per process. Old keys
 * work for one minor (ADR 0130).
 */
export function upgradePermissionKey(
  key: string,
  warn: (message: string) => void = console.warn,
): readonly string[] {
  const next = currentPermissionKeys(key);

  if (isOldPermissionKey(key) && !warned.has(key)) {
    warned.add(key);
    warn(
      `better-supabase: the permission key "${key}" is now ${next.map((each) => `"${each}"`).join(", ")}. Old keys work until the next minor; run \`better-supabase codemod ${RENAMES_CODEMOD}\` to rename them.`,
    );
  }

  return next;
}

/** Split event wildcards whose prefix still has events of its own. */
const KEPT_EVENT_SPLITS: ReadonlySet<string> = /* @__PURE__ */ new Set([
  "drive.*",
  "organization.*",
]);

const eventSplitsOf = (type: string): readonly string[] =>
  Object.hasOwn(EVENT_TYPE_SPLITS, type) ? (EVENT_TYPE_SPLITS[type] ?? []) : [];

/** Whether no block emits `type` any more: it was renamed or split up. */
export const isOldEventType = (type: string): boolean =>
  Object.hasOwn(EVENT_TYPE_RENAMES, type) ||
  (eventSplitsOf(type).length > 0 && !KEPT_EVENT_SPLITS.has(type));

/**
 * Every type or pattern a subscriber to `type` needs now: its rename and the
 * types it was split into. A type that did not change is returned as it is.
 */
export function currentEventTypes(type: string): readonly string[] {
  const own =
    isOldEventType(type) && !Object.hasOwn(EVENT_TYPE_RENAMES, type)
      ? []
      : [renamed(EVENT_TYPE_RENAMES, type)];

  return [...own, ...eventSplitsOf(type)];
}

let legacyEventTypes: ReadonlyMap<string, string> | undefined;

/**
 * The name `type` had before 0.47, for subscribers that still listen for it, or
 * `type` when it was not renamed.
 */
export function legacyEventType(type: string): string {
  legacyEventTypes ??= new Map(
    Object.keys({ ...EVENT_TYPE_RENAMES, ...EVENT_TYPE_SPLITS })
      .filter((old) => !old.endsWith(".*"))
      .flatMap((old) =>
        currentEventTypes(old).map((next) => [next, old] as const),
      ),
  );

  return legacyEventTypes.get(type) ?? type;
}
