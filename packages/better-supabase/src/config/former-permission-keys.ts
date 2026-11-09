import naming from "../../api/naming.json" with { type: "json" };

const PERMISSION_KEY = /^blocks\.([^.]+)\.permissions\.([^.]+)$/;

/**
 * The keys under `blocks.<name>.permissions` that ADR 0130 renamed when the
 * action verbs became `read`, `write` and `manage`, as `<block>.<old action>`
 * and the new action. They are the `configKey` rows of `api/naming.json` for
 * those paths, so `codemod naming` renames what this check refuses.
 */
const FORMER_PERMISSION_KEYS: ReadonlyMap<string, string> = new Map(
  naming.renames.flatMap((rename) => {
    const from = PERMISSION_KEY.exec(rename.from);
    const to = PERMISSION_KEY.exec(rename.to);

    return rename.kind === "configKey" && from !== null && to !== null
      ? [[`${from[1]}.${from[2]}`, to[2]!] as const]
      : [];
  }),
);

/** Throws for a key of `permissions` that is a former action name of `block`. */
export function checkFormerPermissionKeys(
  where: string,
  block: string,
  permissions: Readonly<Record<string, unknown>>,
): void {
  for (const key of Object.keys(permissions)) {
    const renamed = FORMER_PERMISSION_KEYS.get(`${block}.${key}`);

    if (renamed !== undefined) {
      throw new TypeError(
        `${where}.permissions.${key}: renamed to "${renamed}" with ADR 0130. Run \`better-supabase codemod naming\` to rename the key.`,
      );
    }
  }
}
