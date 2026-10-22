import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlFile } from "../../sql/index.ts";

import { moduleSchemaExtensions } from "../../sql/index.ts";
import { applyPlan, changeLines } from "../core/files.ts";
import { migrationsDir, sqlPlan } from "../sql-layout.ts";
import { readSupabaseToml, sqlWorkflow } from "../supabase-toml.ts";
import { stampAfter } from "./migrations.ts";

/** The migration the migrations workflow writes the SQL modules into. */
export const MODULES_SUFFIX = "_better_supabase_modules.sql";

/**
 * The migration `gen` writes the read-sets module into under the migrations
 * workflow.
 */
export const READ_SETS_SUFFIX = "_better_supabase_read_sets.sql";

const UPGRADE_START = "-- @bsb-upgrade-start";
const UPGRADE_END = "-- @bsb-upgrade-end";

/**
 * Whether the project runs the migrations workflow, with no declarative
 * schemas.
 */
export async function writesMigrations(
  config: ResolvedConfig,
): Promise<boolean> {
  return (
    sqlWorkflow(config, await readSupabaseToml(config.root)) === "migrations"
  );
}

/** What goes into one module migration. */
export interface BlockSqlMigrationParts {
  readonly files: readonly BlockSqlFile[];
  /** `sql upgrade` steps, already commented, that run before the schema bodies. */
  readonly upgrade?: readonly string[];
  /** The `realtime.policies` file. */
  readonly topics?: string;
}

/**
 * One migration that holds, in order, the extensions, the upgrade steps, each
 * module's schema body with its `@bsb-block` header, the realtime topic
 * policies and the data statements. Every statement is re-runnable, so a later
 * migration carries all of them, not only the changes.
 */
export function renderModuleMigration(parts: BlockSqlMigrationParts): string {
  const schema = parts.files.filter((file) => file.kind === "schema");
  const data = parts.files.filter((file) => file.kind === "data");
  const modules = [...new Set(schema.map((file) => file.module))];
  const extensions = moduleSchemaExtensions(parts.files);
  const upgrade = parts.upgrade ?? [];

  const sections = [
    [
      `-- better-supabase sql: ${modules.length > 0 ? `the SQL modules ${modules.join(", ")}` : "the realtime topic policies"}, in one migration (sql.workflow: 'migrations').`,
      "-- Managed by `better-supabase sql`, which writes a new migration when they change.",
      "-- Change them through `blocks` in better-supabase.config.ts and the module's SQL hooks.",
    ].join("\n"),
    ...(extensions.length > 0
      ? [extensions.map((extension) => extension.statement).join("\n")]
      : []),
    ...(upgrade.length > 0
      ? [[UPGRADE_START, ...upgrade, UPGRADE_END].join("\n\n")]
      : []),
    ...schema.map((file) => file.contents.trim()),
    ...(parts.topics === undefined ? [] : [parts.topics.trim()]),
    ...data.map((file) => file.contents.trim()),
  ];

  return `${sections.join("\n\n")}\n`;
}

/**
 * The migration without its upgrade steps and package versions, which a later
 * one doesn't repeat.
 */
function comparable(text: string): string {
  return text
    .replaceAll("\r\n", "\n")
    .replace(/\n\n-- @bsb?-upgrade-start\n[\s\S]*?\n-- @bsb?-upgrade-end/, "")
    .replaceAll(
      /^(-- better-supabase module: [^\n(]*?)(?: \([^)]*\))?$/gm,
      "$1",
    );
}

/** Whether two module migrations hold the same modules. */
export const sameModuleMigration = (
  current: string | undefined,
  expected: string,
): boolean =>
  current !== undefined && comparable(current) === comparable(expected);

/** Whether a module migration holds `contents` (one module's file) unchanged. */
export const migrationHolds = (text: string, contents: string): boolean =>
  comparable(text).includes(comparable(contents.trim()));

/** The newest migration that ends in `suffix`, with its text. */
export async function latestMigration(
  config: ResolvedConfig,
  suffix: string,
): Promise<{ readonly path: string; readonly text: string } | undefined> {
  const dir = migrationsDir(config);

  const names: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const latest = names.toSorted().findLast((name) => name.endsWith(suffix));

  if (latest === undefined) {
    return undefined;
  }

  return {
    path: `${dir}/${latest}`,
    text: await readFile(resolve(config.root, dir, latest), "utf-8"),
  };
}

const MODULE_MARKERS = /^-- @(?:bsb-block|bs-module) ([a-z0-9-]+)@(\d+)\b/gm;

/**
 * The modules and versions a module migration installs, from its `@bsb-block`
 * lines.
 */
export function migrationModules(text: string): ReadonlyMap<string, number> {
  return new Map(
    [...text.matchAll(MODULE_MARKERS)].map((match) => [
      match[1]!,
      Number(match[2]),
    ]),
  );
}

/**
 * Writes `contents` as a new migration ending in `suffix`, unless the newest
 * one already holds the same statements. `force` writes it anyway, for upgrade
 * steps that have to run once.
 */
export async function writeLatestMigration(
  config: ResolvedConfig,
  suffix: string,
  contents: string,
  options: {
    readonly now: Date;
    readonly dryRun: boolean;
    readonly force?: boolean;
  },
): Promise<{
  readonly path: string;
  readonly wrote: boolean;
  readonly line: string;
}> {
  const latest = await latestMigration(config, suffix);

  if (
    options.force !== true &&
    latest !== undefined &&
    sameModuleMigration(latest.text, contents)
  ) {
    return {
      path: latest.path,
      wrote: false,
      line: `Unchanged ${latest.path} (it has these statements)`,
    };
  }

  const dir = migrationsDir(config);

  const names: string[] = await readdir(resolve(config.root, dir)).catch(
    () => [],
  );

  const path = `${dir}/${stampAfter(names, options.now)}${suffix}`;

  const applied = await applyPlan(
    sqlPlan(config, {
      regenerate: "better-supabase sql sync",
      files: [{ path, contents }],
    }),
    { "dry-run": options.dryRun },
  );

  return {
    path,
    wrote: applied.mode === "write",
    line: changeLines(applied).join("\n"),
  };
}
