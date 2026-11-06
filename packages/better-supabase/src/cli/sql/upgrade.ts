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
  buildModel,
  conflicts,
  entityRenamePlan,
  moduleFileVersion,
  moduleTopics,
  PRELUDE_FUNCTIONS,
  PRELUDE_MODULE,
  sameBlockFile,
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
  migrationInstances,
  migrationModules,
  MODULES_SUFFIX,
  renderModuleMigration,
  sameModuleMigration,
  writesMigrations,
} from "./module-migration.ts";
import { layoutFor } from "./providers.ts";
import { cacheOf, renderBlocksCached } from "./render-cache.ts";
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

  const files = await renderBlocksCached(
    config,
    config.blockNames,
    sqlLayout,
    cacheOf(args),
  );

  const migrations = await writesMigrations(config);

  const {
    installed,
    stale,
    diffs,
    text,
    files: installedFiles,
  } = migrations
    ? await installedFromMigration(config, sqlLayout, files, paint)
    : await installedFromFiles(config, files, paint);

  const renames = entityRenamePlan(
    config.blockNames,
    installed.map((entry) => entry.module),
    text,
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

  const duplicated = duplicatedPreludeFunctions(installedFiles);

  const data = {
    upgrades: plan.map(({ module, from, to }) => ({ module, from, to })),
    ...(renamed.length > 0 ? { renames: renamed } : {}),
    stale,
    ...(duplicated.length > 0 ? { duplicated } : {}),
  };

  const current =
    plan.length === 0 &&
    stale.length === 0 &&
    renamed.length === 0 &&
    duplicated.length === 0;

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
        ...(stale.length > 0 ? [`Out of date: ${stale.join(", ")}.`] : []),
        ...duplicated,
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

  const steps = [
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
  /** The installed files with their paths; empty for a migration. */
  readonly files: readonly { readonly path: string; readonly text: string }[];
  /** Files a block wrote under its 0.14 name, which `upgrade` removes. */
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
  const paths: { path: string; text: string }[] = [];

  const read = (path: string): Promise<string | undefined> =>
    readFile(resolve(config.root, path), "utf-8").catch(() => undefined);

  for (const file of files) {
    if (file.kind === "data") {
      continue;
    }

    if (file.kind === "test" && SQL_MODULES[file.module]?.target !== "test") {
      continue;
    }

    const found = await read(file.path);

    if (found === undefined) {
      continue;
    }

    const current = found;

    texts.push(found);
    paths.push({ path: file.path, text: found });
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

  return { installed, stale, diffs, text: texts.join("\n"), files: paths };
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
    return { installed: [], stale: [], diffs: [], text: "", files: [] };
  }

  const text = latest.text;
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
    ? { installed, stale: [], diffs: [], text: latest.text, files: [] }
    : {
        installed,
        stale: [latest.path],
        diffs: [fileDiff(latest.path, latest.text, expected, paint)],
        text: latest.text,
        files: [],
      };
}

/**
 * A line for each function of the prelude that a second installed file also
 * creates: a module file written before the prelude existed pastes the helpers
 * it calls, so a schema diff finds each of them twice.
 */
function duplicatedPreludeFunctions(
  files: readonly { readonly path: string; readonly text: string }[],
): string[] {
  const model = buildModel(files);

  return conflicts(model).flatMap(({ declarations }) => {
    const first = declarations[0];

    if (
      first?.kind !== "function" ||
      !PRELUDE_FUNCTIONS.has(
        first.name.slice(first.name.indexOf(".") + 1).replace(/\/\d+$/, ""),
      )
    ) {
      return [];
    }

    return declarations
      .filter(
        (each) =>
          each.owner.kind === "module" && each.owner.name !== PRELUDE_MODULE,
      )
      .map(
        (each) =>
          `${each.file} declares ${first.name.replace(/\/\d+$/, "")}, which the prelude defines. Run \`better-supabase upgrade\`.`,
      );
  });
}
