/**
 * The names the 0.46 naming convention changed (ADR 0130), old to new. The
 * shims, the stored-name migrations, the codemod and doctor read these maps, so
 * each rename is written once.
 */

/** The `better-supabase codemod` version that applies these maps. */
export const RENAMES_CODEMOD = "0.46";

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

/** Outbox event types, old to new. */
export const EVENT_TYPE_RENAMES: Readonly<Record<string, string>> = frozen({});

/** Hint codes in `DbError.details.hint`, old to new. */
export const HINT_RENAMES: Readonly<Record<string, string>> = frozen({});

/** Subject types stored in `subject_type` columns, old to new. */
export const SUBJECT_TYPE_RENAMES: Readonly<Record<string, string>> = frozen(
  {},
);

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
