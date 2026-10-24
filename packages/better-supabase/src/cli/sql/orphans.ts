import { readdir, readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { ResolvedConfig } from "../../config/index.ts";
import type { BlockSqlLayout } from "../../sql/index.ts";

import { CONFIG_DEFAULTS } from "../../config/index.ts";
import {
  isModuleDataFile,
  moduleDataDir,
  moduleFileVersion,
} from "../../sql/index.ts";

/**
 * Block schema and data files in `sql.dir` and the data folder that no
 * installed block renders any more: files of a removed or renamed block, or
 * from an earlier position. Only files with a `@bsb-block` or `@bsb-block-data`
 * line count, so the app's own files are never listed.
 */
export async function orphanedBlockFiles(
  config: ResolvedConfig,
  sqlLayout: BlockSqlLayout,
  rendered: ReadonlySet<string>,
): Promise<string[]> {
  const prefix = sqlLayout.prefix ?? CONFIG_DEFAULTS.sql.prefix;

  const dirs = [
    (sqlLayout.dir ?? CONFIG_DEFAULTS.sql.dir).replace(/\/$/, ""),
    moduleDataDir(sqlLayout),
  ];

  const orphans: string[] = [];

  for (const dir of new Set(dirs)) {
    const entries: string[] = await readdir(resolve(config.root, dir)).catch(
      () => [],
    );

    for (const name of entries.toSorted()) {
      const path = `${dir}/${name}`;

      if (
        !name.startsWith(`${prefix}_`) ||
        !name.endsWith(".sql") ||
        rendered.has(path)
      ) {
        continue;
      }

      const text = await readFile(resolve(config.root, path), "utf-8").catch(
        () => "",
      );

      if (moduleFileVersion(text) !== undefined || isModuleDataFile(text)) {
        orphans.push(path);
      }
    }
  }

  return orphans;
}
