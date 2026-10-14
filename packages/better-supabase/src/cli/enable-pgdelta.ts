import { join } from "node:path";

import { display, writeIfChanged } from "./io.ts";
import {
  diffEngine,
  findSupabaseRoot,
  PGDELTA_TABLE,
  readSupabaseToml,
  tomlGet,
} from "./supabase-toml.ts";

/**
 * Adds `[experimental.pgdelta] enabled = true` to `supabase/config.toml`
 * when it has no such table, so `supabase db schema declarative sync`
 * runs on pg-delta. A table set to `enabled = false` is left alone, and a
 * project without `config.toml` gets nothing.
 */
export async function enablePgDelta(
  root: string,
  dryRun: boolean,
  base: string = root,
): Promise<string[]> {
  const supabaseRoot = findSupabaseRoot(root);
  const toml = await readSupabaseToml(root);
  if (supabaseRoot === undefined || toml === undefined) return [];
  const path = join(supabaseRoot, "supabase/config.toml");
  const shown = display(base, path);
  if (diffEngine(toml) === "pg-delta") return [];
  if (
    tomlGet(toml.document, ["experimental", "pgdelta"]) !== undefined ||
    toml.text.includes("pgdelta")
  ) {
    return [
      `Kept    ${shown} (pg-delta is off; set [experimental.pgdelta] enabled = true, remove [db.migrations] schema_paths and use \`supabase db schema declarative sync\` instead of \`supabase db diff\`)`,
    ];
  }
  if (dryRun) return [`Would enable pg-delta in ${shown}`];
  const separator =
    toml.text === "" || toml.text.endsWith("\n\n")
      ? ""
      : toml.text.endsWith("\n")
        ? "\n"
        : "\n\n";
  await writeIfChanged(path, `${toml.text}${separator}${PGDELTA_TABLE}`);
  return [`Enabled pg-delta in ${shown}`];
}
