import { existsSync } from "node:fs";
import { readdir } from "node:fs/promises";
import { join } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { FilePlan } from "./core/files.ts";
import type { CliEnv } from "./env.ts";
import type { ExistingTable } from "./sql/adopt.ts";

import { loadSnapshot, serializeSnapshot } from "./commands/snapshot.ts";
import { insideRoot } from "./core/files.ts";
import { toCatalog } from "./introspect/index.ts";

/** What `init` finds in a project that already has a Supabase folder. */
export interface ExistingProject {
  readonly migrations: number;
  readonly schemaFiles: number;
  readonly tables: readonly string[];
}

/** Where `init --from <url>` writes the schema it read. */
export const SNAPSHOT_PATH = "supabase/snapshot.json";

const DATABASE_URL = /^postgres(?:ql)?:\/\//u;

/** Whether `--from` names a database rather than a preset, design or file. */
export const isDatabaseUrl = (value: string): boolean =>
  DATABASE_URL.test(value);

async function sqlFiles(dir: string): Promise<number> {
  if (!existsSync(dir)) {
    return 0;
  }

  const entries = await readdir(dir, { withFileTypes: true, recursive: true });

  return entries.filter(
    (entry) => entry.isFile() && entry.name.endsWith(".sql"),
  ).length;
}

/** The tables in the project's saved snapshot, or none without one. */
async function snapshotTables(
  config: ResolvedConfig,
  env: CliEnv,
  root: string,
): Promise<readonly ExistingTable[]> {
  const path = join(root, SNAPSHOT_PATH);

  if (!existsSync(path)) {
    return [];
  }

  try {
    return toCatalog(await loadSnapshot(config, env, { snapshotPath: path }))
      .tables;
  } catch {
    return [];
  }
}

/**
 * The migrations, schema files and snapshot tables of the Supabase folder in
 * `root`, or `undefined` for a project without one.
 */
export async function detectExisting(
  config: ResolvedConfig,
  env: CliEnv,
  root: string,
): Promise<ExistingProject | undefined> {
  const supabase = join(root, "supabase");

  if (!existsSync(supabase)) {
    return undefined;
  }

  const [migrations, schemaFiles, tables] = await Promise.all([
    sqlFiles(join(supabase, "migrations")),
    sqlFiles(join(supabase, "schemas")),
    snapshotTables(config, env, root),
  ]);

  return {
    migrations,
    schemaFiles,
    tables: tables.map((table) => `${table.schema}.${table.name}`),
  };
}

/** The lines `init` prints for an existing project. */
export function existingLines(found: ExistingProject): string[] {
  const counts = [
    `${String(found.migrations)} migration(s)`,
    `${String(found.schemaFiles)} schema file(s)`,
    `${String(found.tables.length)} table(s) in ${SNAPSHOT_PATH}`,
  ].join(", ");

  return [
    `Found an existing Supabase project: ${counts}.`,
    "init changed nothing in the database and added no blocks; each step after it is optional.",
  ];
}

/**
 * Reads the database at `url` and plans a snapshot of its schema, so `gen`,
 * `doctor` and block detection see tables made in the dashboard.
 */
export async function planSnapshotFrom(
  config: ResolvedConfig,
  env: CliEnv,
  root: string,
  url: string,
): Promise<{ readonly plan: FilePlan; readonly tables: number }> {
  const snapshot = await loadSnapshot(config, env, { dbUrl: url, live: true });

  return {
    tables: snapshot.extras.tables.length,
    plan: {
      root,
      regenerate: "better-supabase init --from",
      files: [
        {
          path: insideRoot(root, SNAPSHOT_PATH, "--from"),
          contents: serializeSnapshot(snapshot),
          note: `${String(snapshot.extras.tables.length)} tables`,
        },
      ],
    },
  };
}
