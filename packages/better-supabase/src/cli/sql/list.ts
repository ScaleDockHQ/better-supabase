import { existsSync } from "node:fs";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { CommandResult } from "../io.ts";
import type { SqlFlags } from "./args.ts";

import { moduleFilePaths, SQL_MODULES } from "../../sql/index.ts";
import {
  latestMigration,
  migrationModules,
  MODULES_SUFFIX,
  writesMigrations,
} from "./module-migration.ts";
import { layout } from "./providers.ts";

export async function listModules(
  config: ResolvedConfig,
  args: SqlFlags,
): Promise<CommandResult> {
  const sqlLayout = await layout(config, args);
  const files = moduleFilePaths(Object.keys(SQL_MODULES), sqlLayout);
  const migrated = (await writesMigrations(config))
    ? migrationModules(
        (await latestMigration(config, MODULES_SUFFIX))?.text ?? "",
      )
    : undefined;
  const lines = Object.values(SQL_MODULES).map((module) => {
    const path = files.get(module.name);
    const installed =
      path !== undefined &&
      (migrated === undefined
        ? existsSync(resolve(config.root, path))
        : migrated.has(module.name));
    const tracked = config.sql.moduleNames.includes(module.name);
    const mark =
      path === undefined ? "◇" : installed ? (tracked ? "●" : "○") : " ";
    const requires =
      sqlLayout.entitlementsProvider && module.providerRequires
        ? module.providerRequires
        : module.requires;
    const needs = requires.length > 0 ? ` (needs ${requires.join(", ")})` : "";
    const integrates = module.integrates ?? [];
    const works = integrates.includes("*")
      ? " (works with every installed module)"
      : integrates.length > 0
        ? ` (works with ${integrates.join(", ")})`
        : "";
    return `${mark} ${module.name.padEnd(15)} ${module.description}${needs}${works}`;
  });
  return {
    code: 0,
    output: `${lines.join("\n")}\n\n● installed and in sql.modules   ○ installed, not in sql.modules   ◇ custom mode (the app implements it)`,
  };
}
