import { readdir, readFile, rm } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { SqlFlags } from "./args.ts";

import { CONFIG_DEFAULTS } from "../../config/index.ts";
import {
  type ModuleFile,
  type ModuleLayout,
  moduleTopics,
  renderModules,
  resolveModules,
} from "../../sql/index.ts";
import { enablePgDelta } from "../enable-pgdelta.ts";
import { writeLine } from "../files.ts";
import { display } from "../io.ts";
import {
  migrationCommand,
  readSupabaseToml,
  schemaPaths,
  sqlWorkflow,
} from "../supabase-toml.ts";
import { topicPolicyFile } from "../topic-policies.ts";
import { DATA_NEXT, type Now, writeExtensionsMigration } from "./migrations.ts";
import {
  MODULES_SUFFIX,
  renderModuleMigration,
  writeLatestMigration,
} from "./module-migration.ts";

const MODULE_TEST_MARKER = /^-- @bs-module-test ([a-z0-9-]+)$/m;

/**
 * Test files a SQL module wrote for an earlier layout (a table that is no
 * longer audited), for the modules in `names`.
 */
export async function staleModuleTests(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
  files: readonly ModuleFile[],
): Promise<string[]> {
  const dir = (sqlLayout.testsDir ?? CONFIG_DEFAULTS.sql.testsDir).replace(
    /\/$/,
    "",
  );
  const entries: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );
  const current = new Set(files.map((file) => file.path));
  const modules = new Set(
    resolveModules(names, sqlLayout).map((module) => module.name),
  );
  const stale: string[] = [];
  for (const name of entries.toSorted()) {
    const path = `${dir}/${name}`;
    if (!name.endsWith(".test.sql") || current.has(path)) continue;
    const text = await readFile(resolve(config.root, path), "utf-8");
    const module = MODULE_TEST_MARKER.exec(text)?.[1];
    if (module !== undefined && modules.has(module)) stale.push(path);
  }
  return stale;
}

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
  let data = false;
  const rendered = renderModules(names, sqlLayout);
  const files = rendered.filter(
    (file) => only === undefined || only.includes(file.module),
  );
  for (const path of await staleModuleTests(
    config,
    only ?? names,
    sqlLayout,
    files,
  )) {
    const shown = display(config.root, path);
    if (dryRun) {
      lines.push(`Would remove ${shown}`);
      continue;
    }
    await rm(resolve(config.root, path));
    lines.push(`Removed ${shown}`);
  }
  for (const file of files) {
    if (migrations && file.kind !== "test") continue;
    const path = resolve(config.root, file.path);
    const shown = display(config.root, file.path);
    if (dryRun) {
      lines.push(`Would write ${shown} (${file.module})`);
      continue;
    }
    const { wrote, line } = await writeLine(
      path,
      file.contents,
      shown,
      ` (${file.module})`,
    );
    if (wrote && file.kind === "data") data = true;
    lines.push(line);
  }
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
  if (data) lines.push("", DATA_NEXT);
  if (workflow === "pg-delta")
    lines.push(...(await enablePgDelta(config.root, dryRun)));
  return lines;
}

/** The line that tells the reader how the written modules reach the database. */
export async function nextStep(config: ResolvedConfig): Promise<string> {
  const workflow = sqlWorkflow(config, await readSupabaseToml(config.root));
  return workflow === "migrations"
    ? `Then apply it: ${migrationCommand(workflow)}`
    : `Then create a migration: ${migrationCommand(workflow, "better_supabase_module")}`;
}

/** A note when migra's `schema_paths` is set and misses module files, which `supabase db diff` would then skip. */
export async function unlistedModuleFiles(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: ModuleLayout,
): Promise<string[]> {
  const toml = await readSupabaseToml(config.root);
  const workflow = sqlWorkflow(config, toml);
  if (workflow !== "migra") return [];
  const order = await schemaPaths(config.root, toml, workflow);
  if (!order.configured) return [];
  const supabase = `${toml?.dir ?? "supabase"}/`;
  const unlisted = new Set(order.unlisted);
  const listed = new Set(order.files.filter((path) => !unlisted.has(path)));
  const dir = `${config.sql.dir.replace(/\/$/, "")}/`;
  const missing = renderModules(names, sqlLayout)
    .filter((file) => file.kind !== "data")
    .map((file) => file.path)
    .filter((path) => path.startsWith(dir) && !listed.has(path));
  if (missing.length === 0) return [];
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
