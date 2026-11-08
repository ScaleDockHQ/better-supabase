import { dirname, join } from "node:path";

import { applyPlan } from "./core/files.ts";
import { display } from "./core/io.ts";
import {
  diffEngine,
  findSupabaseRoot,
  PGDELTA_TABLE,
  readSupabaseToml,
  tomlGet,
} from "./supabase-toml.ts";

/**
 * Adds `[experimental.pgdelta] enabled = true` to `supabase/config.toml` when
 * it has no such table, so `supabase db schema declarative sync` runs on
 * pg-delta. A table set to `enabled = false` is left alone, as is a project
 * that lists `[db.migrations] schema_paths`, and a project without
 * `config.toml` gets nothing.
 */
export async function enablePgDelta(
  root: string,
  dryRun: boolean,
  base: string = root,
): Promise<string[]> {
  const supabaseRoot = findSupabaseRoot(root);
  const toml = await readSupabaseToml(root);

  if (supabaseRoot === undefined || toml === undefined) {
    return [];
  }

  const path = join(supabaseRoot, "supabase/config.toml");
  const shown = display(base, path);

  if (diffEngine(toml) === "pg-delta") {
    return [];
  }

  if (
    tomlGet(toml.document, ["experimental", "pgdelta"]) !== undefined ||
    toml.text.includes("pgdelta")
  ) {
    return [
      `Skipped ${shown} (pg-delta is off; set [experimental.pgdelta] enabled = true, remove [db.migrations] schema_paths and use \`supabase db schema declarative sync\` instead of \`supabase db diff\`)`,
    ];
  }

  // A project that lists `[db.migrations] schema_paths` already runs migra;
  // turning pg-delta on would change how its migrations are made.
  const paths = tomlGet(toml.document, ["db", "migrations", "schema_paths"]);

  if (Array.isArray(paths) && paths.length > 0) {
    return [
      `Skipped ${shown} (the project follows migra through [db.migrations] schema_paths; set [experimental.pgdelta] enabled = true, remove schema_paths and use \`supabase db schema declarative sync\` to move to pg-delta)`,
    ];
  }

  const separator =
    toml.text === "" || toml.text.endsWith("\n\n")
      ? ""
      : toml.text.endsWith("\n")
        ? "\n"
        : "\n\n";

  await applyPlan(
    {
      root: dirname(path),
      regenerate: "better-supabase init",
      files: [
        {
          path,
          contents: `${toml.text}${separator}${PGDELTA_TABLE}`,
          policy: "edit",
        },
      ],
    },
    { "dry-run": dryRun },
  );

  return [`${dryRun ? "Would enable" : "Enabled"} pg-delta in ${shown}`];
}
