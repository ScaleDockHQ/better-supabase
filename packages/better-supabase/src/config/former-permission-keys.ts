/**
 * The keys under `blocks.<name>.permissions` that ADR 0130 renamed when the
 * action verbs became `read`, `write` and `manage`, as `<block>.<old action>`
 * and the new action. A config that still has one is refused, and `codemod
 * naming` renames it.
 */
export const FORMER_PERMISSION_KEYS: Readonly<Record<string, string>> =
  Object.freeze({
    "ai-chat.admin": "manage",
    "audit.view": "read",
    "audit.viewAll": "readAll",
    "automations.admin": "manage",
    "automations.edit": "write",
    "billing.viewAll": "readAll",
    "employees.viewSensitive": "readSensitive",
    "impersonation.view": "read",
    "invitations.view": "read",
    "segments.edit": "write",
    "webhooks-in.view": "read",
    "webhooks-out.view": "read",
    "workflow-editor.admin": "manage",
    "workflow-editor.edit": "write",
    "workflows.admin": "manage",
  });

/** Throws for a key of `permissions` that is a former action name of `block`. */
export function checkFormerPermissionKeys(
  where: string,
  block: string,
  permissions: Readonly<Record<string, unknown>>,
): void {
  for (const key of Object.keys(permissions)) {
    const renamed = FORMER_PERMISSION_KEYS[`${block}.${key}`];

    if (renamed !== undefined) {
      throw new TypeError(
        `${where}.permissions.${key}: renamed to "${renamed}" with ADR 0130. Run \`better-supabase codemod naming\` to rename the key.`,
      );
    }
  }
}
