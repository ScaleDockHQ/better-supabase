import type { ResolvedConfig } from "../../config/index.ts";
import type { AnyCommand, CliArgs } from "../core/command.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";

import { defineCliCommand } from "../core/command.ts";
import { applyPlan, PLAN_ARGS, planResult } from "../core/files.ts";
import { commandMeta } from "../core/manifest.ts";
import { appTablePlan } from "../sql/app-table-files.ts";
import { plain } from "../style.ts";

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
 * tags in each table's comment. It reads a config that still has `tables` (the
 * loader accepts it for this command only), so run `upgrade` after removing
 * it.
 */
export async function runMigrateSchemaFirst(
  config: ResolvedConfig,
  args: MigrateSchemaFirstArgs,
  deps: MigrateDeps = {},
): Promise<CommandResult> {
  const built = await appTablePlan(
    config,
    "better-supabase migrate schema-first",
  );

  if (built === undefined) {
    return {
      code: 0,
      output: "The config has no app tables; there are no tables to move.",
      data: { tables: [], files: [] },
    };
  }

  const { plan, tables, files } = built;

  const applied = await applyPlan(plan, args, deps.paint ?? plain);

  const summary =
    applied.mode === "write" && applied.drift
      ? `Wrote ${String(files.length)} files for ${String(tables.length)} tables. Delete \`tables\` from the config and rename \`records\` to \`subjects\`, run \`better-supabase upgrade\` to remove the old app tables file, then \`better-supabase db diff\` to check that the schema is unchanged.`
      : undefined;

  return planResult(plan, applied, {
    data: { tables, files },
    ...(summary === undefined ? {} : { summary }),
  });
}

export const migrateSchemaFirstCommand: AnyCommand = defineCliCommand({
  meta: commandMeta("migrate schema-first"),
  readsLegacyTables: true,
  args: {
    ...MIGRATE_ARGS,
    "dry-run": PLAN_ARGS["dry-run"],
    check: PLAN_ARGS.check,
  },
  run: (args, { config, paint }) =>
    runMigrateSchemaFirst(config, args, { paint }),
});
