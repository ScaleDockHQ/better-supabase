/**
 * The 0.15 `bs_` to `bsb_` rename in the app's own SQL. The upgrade migration
 * renames the objects in the database, but SQL the app wrote (pgTAP tests, its
 * schema files, its newest migration) still names them the old way, so the
 * codemod lists those lines. It never rewrites SQL: a pushed migration must not
 * change, and a test may name an object on purpose.
 */

import { existsSync } from "node:fs";
import { readdir, readFile } from "node:fs/promises";
import { join, relative } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";

import { migrationsDir, schemasDirOf, writtenByBlocks } from "./sql-layout.ts";
import {
  LEGACY_CLAIMS,
  LEGACY_PREFIXES,
  legacyPrefixNames,
} from "./sql/legacy-prefix.ts";

export interface SqlNameHint {
  /** The file, relative to the project root. */
  readonly file: string;
  readonly line: number;
  readonly message: string;
}

interface SqlSource {
  readonly path: string;
  readonly text: string;
}

const LEGACY_NAME = /\bbs_[a-z0-9_]+/g;

const CURRENT_NAME = /\bbsb_[a-z0-9_]+/g;

/**
 * The `bs_` names the 0.15 rename covers, from the files better-supabase wrote:
 * their old `bs_` names before `upgrade` rewrites them, or the `bs_` form of
 * their `bsb_` names after.
 */
function renamedSqlNames(blockFiles: readonly string[]): ReadonlySet<string> {
  const text = blockFiles.join("\n");

  return new Set([
    ...legacyPrefixNames(text),
    ...[...new Set(text.match(CURRENT_NAME))]
      .map((name) => `bs_${name.slice("bsb_".length)}`)
      .filter((name) => !LEGACY_CLAIMS.has(name)),
  ]);
}

const renamed = (name: string, names: ReadonlySet<string>): boolean =>
  names.has(name) || LEGACY_PREFIXES.some((prefix) => name.startsWith(prefix));

/** One hint per line and renamed name in `sources`. */
function sqlNameHints(
  sources: readonly SqlSource[],
  names: ReadonlySet<string>,
): SqlNameHint[] {
  const hints: SqlNameHint[] = [];

  for (const source of sources) {
    for (const [index, line] of source.text.split("\n").entries()) {
      for (const name of new Set(line.match(LEGACY_NAME))) {
        if (renamed(name, names)) {
          hints.push({
            file: source.path,
            line: index + 1,
            message: `${name} is bsb_${name.slice("bs_".length)} since 0.15, and the upgrade migration renames it in the database. Rename it here, in SQL that runs after that migration.`,
          });
        }
      }
    }
  }

  return hints;
}

async function sqlFiles(dir: string): Promise<string[]> {
  if (!existsSync(dir)) {
    return [];
  }

  const files: string[] = [];

  for (const entry of await readdir(dir, { withFileTypes: true })) {
    const full = join(dir, entry.name);

    if (entry.isDirectory()) {
      files.push(...(await sqlFiles(full)));
    } else if (entry.name.endsWith(".sql")) {
      files.push(full);
    }
  }

  return files.toSorted();
}

/**
 * Lines of the app's SQL that name a `bs_` object the 0.15 upgrade renames: the
 * pgTAP tests (`sql.testsDir`), the schema files no block wrote, and the newest
 * migration the app wrote. Older migrations already ran, so they stay as they
 * are.
 */
export async function legacySqlNameHints(
  config: ResolvedConfig,
): Promise<SqlNameHint[]> {
  const read = async (path: string): Promise<SqlSource> => ({
    path: relative(config.root, path).replaceAll("\\", "/"),
    text: await readFile(path, "utf-8"),
  });

  const [tests, schemas, migrations] = await Promise.all([
    Promise.all(
      (await sqlFiles(join(config.root, config.sql.testsDir))).map(read),
    ),
    Promise.all(
      (await sqlFiles(join(config.root, await schemasDirOf(config)))).map(read),
    ),
    Promise.all(
      (await sqlFiles(join(config.root, migrationsDir(config)))).map(read),
    ),
  ]);

  const blockFiles = [...schemas, ...migrations].filter(writtenByBlocks);
  const names = renamedSqlNames(blockFiles.map((file) => file.text));
  const latest = migrations.findLast((file) => !writtenByBlocks(file));

  return sqlNameHints(
    [
      ...tests.filter((file) => !writtenByBlocks(file)),
      ...schemas.filter((file) => !writtenByBlocks(file)),
      ...(latest === undefined ? [] : [latest]),
    ],
    names,
  );
}
