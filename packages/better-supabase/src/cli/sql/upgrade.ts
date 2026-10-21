import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type {
  InstalledModule,
  ModuleFile,
  ModuleLayout,
} from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  entityRenameChanges,
  moduleFileVersion,
  moduleTopics,
  renderModules,
  sameModuleFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { display } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import { migrationStamp } from "./migrations.ts";
import {
  latestMigration,
  migrationModules,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import { nextStep, write } from "./write.ts";

/**
 * Rewrites the module files of modules behind the current version, and writes
 * their upgrade steps (renames, backfills) as a migration that runs before the
 * one the schema diff creates.
 */
export async function upgrade(
  config: ResolvedConfig,
  args: SqlFlags,
  paint: Paint,
  now: Now,
): Promise<CommandResult> {
  if (config.blockNames.length === 0) {
    return {
      code: 0,
      output: "blocks is empty; nothing to upgrade.",
      data: { upgrades: [], stale: [] },
    };
  }

  const sqlLayout = await layoutFor(config, args, config.blockNames);
  const files = renderModules(config.blockNames, sqlLayout);
  const migrations = await writesMigrations(config);

  const { installed, stale, diffs, text } = migrations
    ? await installedFromMigration(config, sqlLayout, files, paint)
    : await installedFromFiles(config, files, paint);

  const renamed = entityRenameChanges(
    installed.map((entry) => entry.module),
    text,
    files.map((file) => file.contents).join("\n"),
  );

  if (renamed.length > 0) {
    return { code: 1, errorCode: "config_invalid", error: renamed.join("\n") };
  }

  const plan = upgradePlan(installed, sqlLayout);

  const data = {
    upgrades: plan.map(({ module, from, to }) => ({ module, from, to })),
    stale,
  };

  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );

  if (args.check === true) {
    if (plan.length === 0 && stale.length === 0) {
      return {
        code: 0,
        output: "SQL modules are at their current versions.",
        data,
      };
    }

    return {
      code: 1,
      errorCode: "check_failed",
      data,
      output: diffs.join("\n\n"),
      error: [
        ...behind,
        ...(stale.length > 0 ? [`Out of date: ${stale.join(", ")}.`] : []),
        "Run `better-supabase sql upgrade`.",
      ].join("\n"),
    };
  }

  if (plan.length === 0 && stale.length === 0) {
    return {
      code: 0,
      output: "SQL modules are at their current versions.",
      data,
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

  if (steps.length > 0 && !migrations) {
    const path = `${migrationsDir(config)}/${migrationStamp(now())}_better_supabase_block_upgrade.sql`;
    const contents = `-- better-supabase sql upgrade: steps that run before the schema diff.\n\n${steps.join("\n\n")}\n`;

    const applied = await applyPlan(
      sqlPlan(config, {
        regenerate: "better-supabase sql upgrade",
        files: [{ path, contents }],
      }),
      { "dry-run": dryRun },
    );

    lines.push(...changeLines(applied));
  }

  for (const entry of plan) {
    lines.push(
      `${entry.module}: version ${String(entry.from)} to ${String(entry.to)}`,
      ...entry.steps.map((step) => `  ${step.description}`),
    );
  }

  lines.push(
    ...(await write(
      config,
      args,
      config.blockNames,
      sqlLayout,
      now,
      undefined,
      migrations ? steps : [],
    )),
  );

  return {
    code: 0,
    output: lines.join("\n"),
    data,
    next: [await nextStep(config)],
  };
}

interface Installed {
  readonly installed: InstalledModule[];
  /** Paths that differ from what this release writes. */
  readonly stale: string[];
  readonly diffs: string[];
  /** The installed files or migration, for their `@bs-entities` lines. */
  readonly text: string;
}

/** The installed versions from the module files in `sql.dir`. */
async function installedFromFiles(
  config: ResolvedConfig,
  files: readonly ModuleFile[],
  paint: Paint,
): Promise<Installed> {
  const installed: InstalledModule[] = [];
  const stale: string[] = [];
  const diffs: string[] = [];
  const texts: string[] = [];

  for (const file of files) {
    if (file.kind === "data") {
      continue;
    }

    if (file.kind === "test" && SQL_MODULES[file.module]?.target !== "test") {
      continue;
    }

    const current = await readFile(
      resolve(config.root, file.path),
      "utf-8",
    ).catch(() => undefined);

    if (current === undefined) {
      continue;
    }

    texts.push(current);
    installed.push({
      module: file.module,
      version: moduleFileVersion(current)?.version ?? 1,
    });

    if (!sameModuleFile(current, file.contents)) {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, paint));
    }
  }

  return { installed, stale, diffs, text: texts.join("\n") };
}

/**
 * The installed versions from the `@bs-module` lines of the newest module
 * migration.
 */
async function installedFromMigration(
  config: ResolvedConfig,
  sqlLayout: ModuleLayout,
  files: readonly ModuleFile[],
  paint: Paint,
): Promise<Installed> {
  const latest = await latestMigration(config, MODULES_SUFFIX);

  if (latest === undefined) {
    return { installed: [], stale: [], diffs: [], text: "" };
  }

  const versions = migrationModules(latest.text);

  const installed = [...versions].map(([module, version]) => ({
    module,
    version,
  }));

  const topics = await topicPolicyFile(
    config,
    moduleTopics(config.blockNames, sqlLayout),
  );

  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics: topics.contents }),
  });

  return sameModuleMigration(latest.text, expected)
    ? { installed, stale: [], diffs: [], text: latest.text }
    : {
        installed,
        stale: [latest.path],
        diffs: [fileDiff(latest.path, latest.text, expected, paint)],
        text: latest.text,
      };
}
