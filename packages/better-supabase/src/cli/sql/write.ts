import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlFile, BlockSqlLayout } from "../../sql/index.ts";
import type { PlannedFile, Removal } from "../core/files.ts";
import type { NextStep } from "../core/io.ts";
import type { SqlFlags } from "./args.ts";
import type { Now } from "./migrations.ts";

import { CONFIG_DEFAULTS } from "../../config/index.ts";
import {
  APP_TABLES_MARKER,
  APP_TABLES_MODULE,
  currentBlockName,
  moduleTopics,
  renderBlocks,
  resolveBlocks,
  sameBlockFile,
} from "../../sql/index.ts";
import {
  applyPlan,
  changeLines,
  HAND_EDITED,
  handEditedError,
  keepHandEdit,
} from "../core/files.ts";
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
import { orphanedBlockFiles } from "./orphans.ts";

const MODULE_TEST_MARKER =
  /^-- @(?:bsb-block-test|bs-module-test) ([a-z0-9-]+)$/m;

/**
 * Test files a SQL module wrote for an earlier layout (a table that is no
 * longer audited), for the modules in `names`. With `appTables`, also the app
 * tables files once `appTables` is empty.
 */
export async function staleModuleTests(
  config: ResolvedConfig,
  names: readonly string[],
  sqlLayout: BlockSqlLayout,
  files: readonly BlockSqlFile[],
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
    ...resolveBlocks(names, sqlLayout).map((module) => module.name),
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

    if (module !== undefined && modules.has(currentBlockName(module))) {
      stale.push(path);
    }
  }

  return stale;
}

/** The app tables schema file, when `appTables` no longer renders it. */
async function staleAppTablesSchema(
  config: ResolvedConfig,
  sqlLayout: BlockSqlLayout,
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

  return text
    .split("\n")
    .some((line) => line === APP_TABLES_MARKER || line === "-- @bs-app-tables")
    ? [path]
    : [];
}

/** A rendered module file as a plan entry, compared without its module version. */
export const moduleFile = (file: BlockSqlFile): PlannedFile => ({
  path: file.path,
  contents: file.contents,
  note: file.module,
  policy: "block",
  same: sameBlockFile,
});

/** A removal that stays when the file was edited by hand. */
export const guardedRemoval = (path: string): Removal => ({
  path,
  keep: keepHandEdit,
});

export interface SqlWrite {
  readonly lines: readonly string[];
  /** Set when a hand-edited block file was left alone. */
  readonly error?: string;
}

export async function write(
  config: ResolvedConfig,
  args: SqlFlags,
  names: readonly string[],
  sqlLayout: BlockSqlLayout,
  now: Now,
  only?: readonly string[],
  upgrade: readonly string[] = [],
  former: readonly string[] = [],
): Promise<SqlWrite> {
  const workflow = sqlWorkflow(config, await readSupabaseToml(config.root));
  const migrations = workflow === "migrations";
  const lines: string[] = [];
  const dryRun = args["dry-run"] === true;
  const rendered = renderBlocks(names, sqlLayout);

  const files = rendered.filter(
    (file) => only === undefined || only.includes(file.module),
  );

  const written = files.filter((file) => !migrations || file.kind === "test");

  const orphans =
    only === undefined && !migrations
      ? await orphanedBlockFiles(
          config,
          sqlLayout,
          new Set(files.map((file) => file.path)),
        )
      : [];

  const applied = await applyPlan(
    sqlPlan(config, {
      regenerate: "better-supabase upgrade",
      files: written.map((file) => moduleFile(file)),
      remove: [
        ...new Set([
          ...former,
          ...orphans,
          ...(await staleModuleTests(
            config,
            only ?? names,
            sqlLayout,
            files,
            only === undefined,
          )),
        ]),
      ].map((path) => guardedRemoval(path)),
    }),
    { "dry-run": dryRun, force: args.force === true },
  );

  lines.push(...changeLines(applied));

  const edited = applied.changes
    .filter((change) => change.reason === HAND_EDITED)
    .map((change) => change.file);

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

    return {
      lines,
      ...(edited.length === 0 ? {} : { error: handEditedError(edited) }),
    };
  }

  lines.push(...(await writeExtensionsMigration(config, files, dryRun, now)));

  if (data) {
    lines.push("", DATA_NEXT);
  }

  if (workflow === "pg-delta") {
    lines.push(...(await enablePgDelta(config.root, dryRun)));
  }

  return {
    lines,
    ...(edited.length === 0 ? {} : { error: handEditedError(edited) }),
  };
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
  sqlLayout: BlockSqlLayout,
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

  const missing = renderBlocks(names, sqlLayout)
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
