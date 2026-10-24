import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type {
  InstalledBlock,
  BlockSqlFile,
  BlockSqlLayout,
} from "../../sql/index.ts";
import type { CommandResult } from "../core/io.ts";
import type { Paint } from "../style.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import {
  entityRenamePlan,
  moduleFileVersion,
  moduleTopics,
  renderBlocks,
  sameBlockFile,
  SQL_MODULES,
  upgradePlan,
} from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { display } from "../core/io.ts";
import { fileDiff } from "../diff.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import {
  legacyBlocksTableSql,
  legacyPrefixNames,
  legacyPrefixSql,
} from "./legacy-prefix.ts";
import { migrationStamp } from "./migrations.ts";
import {
  latestMigration,
  migrationInstances,
  migrationModules,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import {
  formerPaths,
  renamedBlocksIn,
  renamedBlocksSql,
  withCurrentBlockNames,
} from "./renamed-blocks.ts";
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
  const files = renderBlocks(config.blockNames, sqlLayout);
  const migrations = await writesMigrations(config);

  const { installed, stale, diffs, text, former } = migrations
    ? await installedFromMigration(config, sqlLayout, files, paint)
    : await installedFromFiles(config, files, paint);

  const renames = entityRenamePlan(
    config.blockNames,
    installed.map((entry) => entry.module),
    withCurrentBlockNames(text),
    sqlLayout,
  );

  if (renames.refused.length > 0) {
    return {
      code: 1,
      errorCode: "config_invalid",
      error: renames.refused.join("\n"),
    };
  }

  const plan = upgradePlan(installed, sqlLayout);
  const renamed = [...new Set(renames.steps.map((step) => step.module))];
  const legacy = legacyPrefixNames(text);
  const blockRenames = renamedBlocksIn(text);
  const prefixed = legacy.length > 0;
  const modulesTable = text.includes("better_supabase.modules");

  const data = {
    upgrades: plan.map(({ module, from, to }) => ({ module, from, to })),
    ...(renamed.length > 0 ? { renames: renamed } : {}),
    ...(prefixed ? { prefix: "bsb" } : {}),
    ...(modulesTable ? { table: "better_supabase.blocks" } : {}),
    ...(blockRenames.length > 0 ? { blocks: blockRenames } : {}),
    stale,
  };

  const current =
    plan.length === 0 &&
    stale.length === 0 &&
    renamed.length === 0 &&
    !prefixed &&
    !modulesTable &&
    blockRenames.length === 0;

  const behind = plan.map(
    (entry) =>
      `${entry.module} is at version ${String(entry.from)}; the current version is ${String(entry.to)}`,
  );

  if (args.check === true) {
    if (current) {
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
        ...renamed.map(
          (module) => `${module} has entity renames to apply to its tables`,
        ),
        ...(prefixed
          ? ["The installed objects still use the bs_ prefix of 0.14 and older"]
          : []),
        ...(modulesTable
          ? [
              "The installed versions are in better_supabase.modules, which 0.15 names better_supabase.blocks",
            ]
          : []),
        ...blockRenames.map(
          ({ from, to }) =>
            `The ${from} block is installed; 0.15 names it ${to}`,
        ),
        ...(stale.length > 0 ? [`Out of date: ${stale.join(", ")}.`] : []),
        "Run `better-supabase upgrade`.",
      ].join("\n"),
    };
  }

  if (current) {
    return {
      code: 0,
      output: "SQL modules are at their current versions.",
      data,
    };
  }

  const lines: string[] = [];

  const renameSteps =
    renames.steps.length === 0
      ? []
      : [
          `-- Entity renames (blocks.<name>.entities) of ${renamed.join(", ")}.\n${renames.steps.map((step) => step.sql).join("\n")}`,
        ];

  const prefixSteps = prefixed
    ? [
        `-- Renames the bs_ triggers, policies, constraints, indexes and functions to bsb_ (0.15).\n${legacyPrefixSql(legacy)}`,
      ]
    : [];

  const tableSteps = modulesTable
    ? [
        `-- Copies better_supabase.modules into better_supabase.blocks (0.15).\n${legacyBlocksTableSql}`,
      ]
    : [];

  const blockSteps =
    blockRenames.length === 0
      ? []
      : [
          `-- Moves the installed blocks 0.15 renamed to their new names.\n${renamedBlocksSql(blockRenames)}`,
        ];

  const steps = [
    ...tableSteps,
    ...blockSteps,
    ...prefixSteps,
    ...renameSteps,
    ...plan.flatMap((entry) =>
      entry.steps
        .filter((step) => step.sql !== "")
        .map(
          (step) =>
            `-- ${entry.module}: version ${String(step.from)} to ${String(step.from + 1)}. ${step.description}\n${step.sql}`,
        ),
    ),
  ];

  const dryRun = args["dry-run"] === true;

  if (steps.length > 0 && !migrations) {
    const path = `${migrationsDir(config)}/${migrationStamp(now())}_better_supabase_block_upgrade.sql`;
    const contents = `-- better-supabase upgrade: steps that run before the schema diff.\n\n${steps.join("\n\n")}\n`;

    const applied = await applyPlan(
      sqlPlan(config, {
        regenerate: "better-supabase upgrade",
        files: [{ path, contents }],
      }),
      { "dry-run": dryRun },
    );

    lines.push(...changeLines(applied));
  }

  if (modulesTable) {
    lines.push("Copied better_supabase.modules into better_supabase.blocks");
  }

  if (prefixed) {
    lines.push(`Renamed ${String(legacy.length)} bs_ names to bsb_`);
  }

  for (const { from, to } of blockRenames) {
    lines.push(`Renamed the ${from} block to ${to}`);
  }

  for (const module of renamed) {
    lines.push(`${module}: renamed after blocks.<name>.names`);
  }

  for (const entry of plan) {
    lines.push(
      `${entry.module}: version ${String(entry.from)} to ${String(entry.to)}`,
      ...entry.steps.map((step) => `  ${step.description}`),
    );
  }

  const written = await write(
    config,
    args,
    config.blockNames,
    sqlLayout,
    now,
    undefined,
    migrations ? steps : [],
    former,
  );

  lines.push(...written.lines);

  return {
    code: written.error === undefined ? 0 : 1,
    output: lines.join("\n"),
    ...(written.error === undefined
      ? {}
      : { error: written.error, errorCode: "file_conflict" as const }),
    data,
    next: [await nextStep(config)],
  };
}

interface Installed {
  readonly installed: InstalledBlock[];
  /** Paths that differ from what this release writes. */
  readonly stale: string[];
  readonly diffs: string[];
  /** The installed files or migration, for their `@bsb-names` lines. */
  readonly text: string;
  /** Files a block wrote under its 0.14 name, which `upgrade` removes. */
  readonly former: readonly string[];
}

/** The installed versions from the module files in `sql.dir`. */
async function installedFromFiles(
  config: ResolvedConfig,
  files: readonly BlockSqlFile[],
  paint: Paint,
): Promise<Installed> {
  const installed: InstalledBlock[] = [];
  const stale: string[] = [];
  const diffs: string[] = [];
  const texts: string[] = [];
  const former: string[] = [];

  const read = (path: string): Promise<string | undefined> =>
    readFile(resolve(config.root, path), "utf-8").catch(() => undefined);

  for (const file of files) {
    const earlier = formerPaths(file.path, file.module);
    let formerText: string | undefined;

    for (const formerPath of earlier) {
      const text = await read(formerPath);

      if (text !== undefined) {
        former.push(formerPath);
        formerText ??= text;
      }
    }

    if (file.kind === "data") {
      continue;
    }

    if (file.kind === "test" && SQL_MODULES[file.module]?.target !== "test") {
      continue;
    }

    const found = (await read(file.path)) ?? formerText;

    if (found === undefined) {
      continue;
    }

    const current = withCurrentBlockNames(found);

    texts.push(found);
    installed.push({
      module: file.instance ?? file.module,
      ...(file.instance === undefined ? {} : { block: file.module }),
      version: moduleFileVersion(current)?.version ?? 1,
    });

    if (!sameBlockFile(current, file.contents)) {
      const shown = display(config.root, file.path);
      stale.push(shown);
      diffs.push(fileDiff(shown, current, file.contents, paint));
    }
  }

  return { installed, stale, diffs, text: texts.join("\n"), former };
}

/**
 * The installed versions from the `@bsb-block` lines of the newest module
 * migration.
 */
async function installedFromMigration(
  config: ResolvedConfig,
  sqlLayout: BlockSqlLayout,
  files: readonly BlockSqlFile[],
  paint: Paint,
): Promise<Installed> {
  const latest = await latestMigration(config, MODULES_SUFFIX);

  if (latest === undefined) {
    return { installed: [], stale: [], diffs: [], text: "", former: [] };
  }

  const text = withCurrentBlockNames(latest.text);
  const versions = migrationModules(text);
  const blocks = migrationInstances(text);

  const installed = [...versions].map(([module, version]) => {
    const block = blocks.get(module);

    return { module, ...(block === undefined ? {} : { block }), version };
  });

  const topics = await topicPolicyFile(
    config,
    moduleTopics(config.blockNames, sqlLayout),
  );

  const expected = renderModuleMigration({
    files,
    ...(topics === undefined ? {} : { topics: topics.contents }),
  });

  return sameModuleMigration(latest.text, expected)
    ? { installed, stale: [], diffs: [], text: latest.text, former: [] }
    : {
        installed,
        stale: [latest.path],
        diffs: [fileDiff(latest.path, latest.text, expected, paint)],
        text: latest.text,
        former: [],
      };
}
