import type { Preset } from "../preset/index.ts";
import type { AppTable } from "./design.ts";
import type { SchemaColumn } from "./schema.ts";

export const AUTH_USERS = "auth.users";

/**
 * The column that scopes an app table's rows, or `null` for `scope: "none"` and
 * unscoped presets.
 */
export function scopeColumnOf(
  table: AppTable,
  preset: Pick<Preset, "scope" | "tenantName" | "idType">,
): SchemaColumn | null {
  const scope = table.scope ?? "inherit";

  if (scope === "none") {
    return null;
  }

  if (scope === "inherit" && preset.scope === "tenant") {
    return {
      name: `${preset.tenantName}_id`,
      type: preset.idType,
      nullable: false,
      default: null,
      unique: false,
    };
  }

  if (scope === "user" || preset.scope === "user") {
    return {
      name: "user_id",
      type: "uuid",
      nullable: false,
      default: "auth.uid()",
      unique: false,
    };
  }

  return null;
}
