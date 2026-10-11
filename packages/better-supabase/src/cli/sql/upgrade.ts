import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../io.ts";
import type { SqlFlags } from "./args.ts";

import {
  type InstalledModule,
  type ModuleFile,
  moduleFileVersion,
  renderModules,
  sameModuleFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { fileDiff } from "../diff.ts";
import { display, writeIfChanged } from "../io.ts";
import { migrationsDir } from "../sql-layout.ts";
import { type Paint } from "../style.ts";
import { migrationCommand, readSupabaseToml } from "../supabase-toml.ts";
import { migrationStamp, type Now } from "./migrations.ts";
import { layoutFor } from "./providers.ts";
import { write } from "./write.ts";

/**
 * Rewrites the module files of modules behind the current version, and writes
 * their upgrade steps (renames, backfills) as a migration that runs before
 * the one the schema diff creates.
 */
export async function upgrade(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint,
  now: Now,
): Promise<CommandResult> {
  if (config.sql.moduleNames.length === 0) {
    return { code: 0, output: "sql.modules is empty; nothing to upgrade." };
  }
  const sqlLayout = await layoutFor(config, args, config.sql.moduleNames);
  const files = renderModules(config.sql.moduleNames, sqlLayout);
  const installed: InstalledModule[] = [];
  const stale: ModuleFile[] = [];
  const diffs: string[] = [];
  for (const file of files) {
    if (file.kind === "data") continue;
    if (file.kind === "test" && SQL_MODULES[file.module]?.target !== "test")
      continue;
    const current = await readFile(
      resolve(config.root, file.path),
      "utf8",
    ).catch(() => undefined);
    if (current === undefined) continue;
    installed.push({
      module: file.module,
      version: moduleFileVersion(current)?.version ?? 1,
    });
    if (!sameModuleFile(current, file.contents)) {
      stale.push(file);
      diffs.push(
        fileDiff(
          display(config.root, file.path),
          current,
          file.contents,
          paint,
        ),
      );
    }
  }
  const plan = upgradePlan(installed, sqlLayout);
  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );
  if (args.check === true) {
    if (plan.length === 0 && stale.length === 0) {
      return {
        code: 0,
        output: "SQL modules are at their current versions.",
      };
    }
    return {
      code: 1,
      output: diffs.join("\n\n"),
      error: [
        ...behind,
        ...(stale.length > 0
          ? [
              `Out of date: ${stale.map((file) => display(config.root, file.path)).join(", ")}.`,
            ]
          : []),
        "Run `better-supabase sql upgrade`.",
      ].join("\n"),
    };
  }
  if (plan.length === 0 && stale.length === 0) {
    return {
      code: 0,
      output: "SQL modules are at their current versions.",
    };
  }
  const lines: string[] = [];
  const steps = plan.flatMap((entry) =>
    entry.steps
      .filter((step) => step.sql !== "")
      .map(
        (step) =>
          `-- ${entry.module}: version ${String(step.from)} to ${String(step.from + 1)}. ${step.description}\n${step.sql}`,
      ),
  );
  const dryRun = args["dry-run"] === true;
  if (steps.length > 0) {
    const path = `${migrationsDir(config)}/${migrationStamp(now())}_better_supabase_block_upgrade.sql`;
    const contents = `-- better-supabase sql upgrade: steps that run before the schema diff.\n\n${steps.join("\n\n")}\n`;
    if (dryRun) {
      lines.push(`Would write ${path}`);
    } else {
      await writeIfChanged(resolve(config.root, path), contents);
      lines.push(`Wrote ${path}`);
    }
  }
  for (const entry of plan) {
    lines.push(
      `${entry.module}: version ${String(entry.from)} to ${String(entry.to)}`,
      ...entry.steps.map((step) => `  ${step.description}`),
    );
  }
  lines.push(
    ...(await write(config, args, config.sql.moduleNames, sqlLayout, now)),
    "",
    `Then create a migration: ${migrationCommand(await readSupabaseToml(config.root), "better_supabase_module")}`,
  );
  return { code: 0, output: lines.join("\n") };
}
