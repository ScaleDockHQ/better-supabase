/**
 * The stored names the 0.36 naming convention renames (ADR 0123). The CLI's
 * data step and the `codemod 0.36` rename read these maps, so a rename lands in
 * one place.
 */

/** Old permission key to new, with a `*` wildcard for a whole area. */
export const PERMISSION_KEY_RENAMES: Readonly<Record<string, string>> = {
  "activity.read": "timeline.read",
  "controls.*": "compliance.*",
  "custom_fields.sensitive.read": "custom_fields.read_sensitive",
  "engagements.*": "activities.*",
  "history.*": "field_history.*",
  "mail.*": "mail_sync.*",
  "number_sequences.*": "numbering.*",
  "organization.export": "data_lifecycle.export",
  "parties.*": "contacts.*",
  "rules.admin": "automations.manage",
  "rules.edit": "automations.write",
  "rules.publish": "automations.publish",
  "rules.read": "automations.read",
  "segments.edit": "segments.write",
  "service_principals.*": "service_accounts.*",
  "support.*": "impersonation.*",
  "targets.*": "goals.*",
  "views.*": "saved_views.*",
  "work_items.*": "tasks.*",
  "workflow.*": "workflows.*",
} as const;

/** Old event type to new. */
export const EVENT_TYPE_RENAMES: Readonly<Record<string, string>> = {} as const;

/** Old hint code to new. */
export const HINT_RENAMES: Readonly<Record<string, string>> = {} as const;

/** Old stored subject type to new. */
export const SUBJECT_TYPE_RENAMES: Readonly<Record<string, string>> = {} as const;

/** `value` through `map`, or `value` when the map has no entry. */
export function renamed(
  map: Readonly<Record<string, string>>,
  value: string,
): string {
  return map[value] ?? value;
}

/** The old keys a new permission key came from, for a migration. */
export function previousPermissionKeys(key: string): readonly string[] {
  return Object.entries(PERMISSION_KEY_RENAMES)
    .filter(([, next]) => next === key)
    .map(([before]) => before);
}
