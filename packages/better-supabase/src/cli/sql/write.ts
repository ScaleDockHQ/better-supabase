import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { ModuleFile, ModuleLayout } from "../../sql/index.ts";
import type { PlannedFile } from "../core/files.ts";
import type { NextStep } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import { CONFIG_DEFAULTS } from "../../config/index.ts";
import {
  APP_TABLES_MARKER,
  APP_TABLES_MODULE,
  moduleTopics,
  renderModules,
  resolveModules,
  sameModuleFile,
} from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { enablePgDelta } from "../enable-pgdelta.ts";
import { sqlPlan } from "../sql-layout.ts";
import {
  migrationCommand,
  readSupabaseToml,
  schemaPaths,
  sqlWorkflow,
} from "../supabase-toml.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import { DATA_NEXT, writeExtensionsMigration } from "./migrations.ts";
import {
  MODULES_SUFFIX,
  renderModuleMigration,
  writeLatestMigration,
} from "./module-migration.ts";

const MODULE_TEST_MARKER = /^-- @bs-module-test ([a-z0-9-]+)$/m;

/**
 * Test files a SQL module wrote for an earlier layout (a table that is no
 * longer audited), for the modules in `names`. With `appTables`, also the app
 * tables files once `appTables` is empty.
 */
export async function staleModuleTests(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
  files: readonly ModuleFile[],
  appTables = true,
): Promise<string[]> {
  const dir = (sqlLayout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );

  const entries: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const current = new Set(files.map((file) => file.path));

  const modules = new Set([
    ...resolveModules(names, sqlLayout).map((module) => module.name),
    ...(appTables ? [APP_TABLES_MODULE] : []),
  ]);

  const stale: string[] = appTables
    ? await staleAppTablesSchema(config, sqlLayout, current)
    : [];

  for (const name of entries.toSorted()) {
    const path = `${dir}/${name}`;

    if (!name.endsWith(".test.sql") || current.has(path)) {
      continue;
    }

    const text = await readFile(resolve(config.root, path), "utf-8");
    const module = MODULE_TEST_MARKER.exec(text)?.[1];

    if (module !== undefined && modules.has(module)) {
      stale.push(path);
    }
  }

  return stale;
}

/** The app tables schema file, when `appTables` no longer renders it. */
async function staleAppTablesSchema(
  config: ResolvedConfig,
  sqlLayout: ModuleLayout,
  current: ReadonlySet<string>,
): Promise<string[]> {
  const dir = (sqlLayout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, "");
  const path = `${dir}/${sqlLayout.prefix ?? CONFIG_DEFAULTS.sql.prefix}_app_tables.sql`;

  if (current.has(path)) {
    return [];
  }

  const text = await readFile(resolve(config.root, path), "utf-8").catch(
    () => "",
  );

  return text.split("\n").includes(APP_TABLES_MARKER) ? [path] : [];
}

/** A rendered module file as a plan entry, compared without its module version. */
export const moduleFile = (file: ModuleFile): PlannedFile => ({
  path: file.path,
  contents: file.contents,
  note: file.module,
  same: sameModuleFile,
});

export async function write(
  config: ResolvedConfig,
  args: SqlFlags,
  names: readonly string[],
  sqlLayout: ModuleLayout,
  now: Now,
  only?: readonly string[],
  upgrade: readonly string[] = [],
): Promise<string[]> {
  const workflow = sqlWorkflow(config, await readSupabaseToml(config.root));
  const migrations = workflow === "migrations";
  const lines: string[] = [];
  const dryRun = args["dry-run"] === true;
  const rendered = renderModules(names, sqlLayout);

  const files = rendered.filter(
    (file) => only === undefined || only.includes(file.module),
  );

  const written = files.filter((file) => !migrations || file.kind === "test");

  const applied = await applyPlan(
    sqlPlan(config, {
      regenerate: "better-supabase sql sync",
      files: written.map((file) => moduleFile(file)),
      remove: await staleModuleTests(
        config,
        only ?? names,
        sqlLayout,
        files,
        only === undefined,
      ),
    }),
    { "dry-run": dryRun },
  );

  lines.push(...changeLines(applied));

  const data =
    !dryRun &&
    applied.changes.some(
      (change, index) =>
        (change.outcome === "create" || change.outcome === "update") &&
        written[index]?.kind === "data",
    );

  if (migrations) {
    const topics = await topicPolicyFile(
      config,
      moduleTopics(names, sqlLayout),
    );

    const written = await writeLatestMigration(
      config,
      MODULES_SUFFIX,
      renderModuleMigration({
        files: rendered,
        upgrade,
        ...(topics === undefined ? {} : { topics: topics.contents }),
      }),
      { now: now(), dryRun, force: upgrade.length > 0 },
    );

    lines.push(written.line);

    return lines;
  }

  lines.push(...(await writeExtensionsMigration(config, files, dryRun, now)));

  if (data) {
    lines.push("", DATA_NEXT);
  }

  if (workflow === "pg-delta") {
    lines.push(...(await enablePgDelta(config.root, dryRun)));
  }

  return lines;
}

/** The command that takes the written modules to the database. */
export async function nextStep(config: ResolvedConfig): Promise<NextStep> {
  const workflow = sqlWorkflow(config, await readSupabaseToml(config.root));

  return workflow === "migrations"
    ? { command: migrationCommand(workflow), when: "applies the migration" }
    : {
        command: migrationCommand(workflow, "better_supabase_module"),
        when: "creates a migration from the module files",
      };
}

/**
 * A note when migra's `schema_paths` is set and misses module files, which
 * `supabase db diff` would then skip.
 */
export async function unlistedModuleFiles(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
): Promise<string[]> {
  const toml = await readSupabaseToml(config.root);
  const workflow = sqlWorkflow(config, toml);

  if (workflow !== "migra") {
    return [];
  }

  const order = await schemaPaths(config.root, toml, workflow);

  if (!order.configured) {
    return [];
  }

  const supabase = `${toml?.dir ?? "supabase"}/`;
  const unlisted = new Set(order.unlisted);
  const listed = new Set(order.files.filter((path) => !unlisted.has(path)));
  const dir = `${config.sql.dir.replace(/\/$/, "")}/`;

  const missing = renderModules(names, sqlLayout)
    .filter((file) => file.kind !== "data")
    .map((file) => file.path)
    .filter((path) => path.startsWith(dir) && !listed.has(path));

  if (missing.length === 0) {
    return [];
  }

  return [
    "",
    `${toml?.path ?? "supabase/config.toml"} sets [db.migrations] schema_paths, and no entry matches these files, so \`supabase db diff\` skips them.`,
    "Add them before the schemas that call their functions:",
    ...missing.map(
      (path) =>
        `  "./${path.startsWith(supabase) ? path.slice(supabase.length) : path}",`,
    ),
    "Or switch to pg-delta, which orders the files by dependency: add [experimental.pgdelta] with enabled = true and remove schema_paths (doctor BS316).",
  ];
}
