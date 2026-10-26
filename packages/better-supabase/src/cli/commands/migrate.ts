import { join } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { FilePlan } from "../core/files.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";

import { APP_TABLES_MODULE, renderBlocks } from "../../sql/index.ts";
import { defineCliCommand } from "../core/command.ts";
import { CliError } from "../core/errors.ts";
import { applyPlan, PLAN_ARGS, planResult } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { layoutFor } from "../sql/providers.ts";
import { splitAppTables } from "../sql/schema-first.ts";
import { plain } from "../style.ts";
import { declarativeSchemasDir, readSupabaseToml } from "../supabase-toml.ts";

const MIGRATE_ARGS = {} as const;

export type MigrateSchemaFirstArgs = CliArgs<
  typeof MIGRATE_ARGS & Pick<typeof PLAN_ARGS, "dry-run" | "check">
>;

/** What `runMigrateSchemaFirst` reads from outside. */
export interface MigrateDeps {
  readonly paint?: Paint;
}

/**
 * Writes the tables that `appTables` renders as files you own under
 * `supabase/schemas` (ADR 0102), with the config's per-table features as `@bsb`
 * tags in each table's comment. The config keeps working until you delete
 * `appTables`, so run `upgrade` after removing it.
 */
export async function runMigrateSchemaFirst(
  config: ResolvedConfig,
  args: MigrateSchemaFirstArgs,
  deps: MigrateDeps = {},
): Promise<CommandResult> {
  const tables = Object.keys(config.appTables);

  if (tables.length === 0) {
    return {
      code: 0,
      output: "appTables is empty; there are no tables to move.",
      data: { tables: [], files: [] },
    };
  }

  const layout = await layoutFor(config, {}, config.blockNames);
  const rendered = renderBlocks(config.blockNames, layout);

  const source = rendered.find(
    (file) => file.module === APP_TABLES_MODULE && file.kind === "schema",
  );

  if (source === undefined) {
    throw new CliError("usage", "The config renders no app tables file.");
  }

  const dir = join(
    config.root,
    declarativeSchemasDir(await readSupabaseToml(config.root)),
  );

  const files = splitAppTables(config, source.contents, tables);

  const plan: FilePlan = {
    root: config.root,
    regenerate: "better-supabase migrate schema-first",
    files: files.map((file) => ({
      path: join(dir, file.path),
      contents: file.contents,
      policy: "create",
    })),
  };

  const applied = await applyPlan(plan, args, deps.paint ?? plain);

  const summary =
    applied.mode === "write" && applied.drift
      ? `Wrote ${String(files.length)} files for ${String(tables.length)} tables. Delete appTables (and records) from the config, run \`better-supabase upgrade\` to remove the old app tables file, then \`better-supabase db diff\` to check that the schema is unchanged.`
      : undefined;

  return planResult(plan, applied, {
    data: { tables, files: files.map((file) => file.path) },
    ...(summary === undefined ? {} : { summary }),
  });
}

export const migrateSchemaFirstCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("migrate schema-first"),
  args: {
    ...MIGRATE_ARGS,
    "dry-run": PLAN_ARGS["dry-run"],
    check: PLAN_ARGS.check,
  },
  run: (args, { config, paint }) =>
    runMigrateSchemaFirst(config, args, { paint }),
});
