import { readFile } from "node:fs/promises";
import { resolve } from "node:path";

import type { BlockSqlFile } from "../../sql/index.ts";
import type { DoctorContext } from "./rules.ts";

import { moduleFileVersion, renderBlocks } from "../../sql/index.ts";
import { migrationsDir, moduleLayoutFor } from "../sql-layout.ts";
import {
  latestMigration,
  migrationHolds,
  migrationModules,
  MODULES_SUFFIX,
} from "../sql/module-migration.ts";
import { accessModule, entitlementsModule } from "./authorization.ts";
import { permissionCatalogKeys, workflowOf } from "./shared.ts";

export interface BlockSqlFileState {
  readonly file: BlockSqlFile;
  /**
   * Where the module lives: its file, or the module migration under the
   * migrations workflow.
   */
  readonly path: string;
  /**
   * The installed text, or the rendered one when the module migration holds it
   * unchanged.
   */
  readonly current: string | undefined;
  /** The installed `@bsb-block` version (1 without one). */
  readonly installed?: number | undefined;
  /** The file's `@bsb-block` version (1 without one) is below the module's. */
  readonly behind: boolean;
}

/** The `blocks` files as this release renders them, next to what is on disk. */
export async function moduleFiles(
  context: DoctorContext,
): Promise<BlockSqlFileState[]> {
  if (
    context.config.blockNames.length === 0 &&
    Object.keys(context.config.appTables).length === 0
  ) {
    return [];
  }

  // BS411 reports a provider access model the provider can't back; the module
  // can't render without it, so there is nothing to compare.
  const access = accessModule(context);

  if (access.kind === "invalid") {
    return [];
  }

  const readSets = context.readSets;
  const skipped = readSets !== undefined && "skipped" in readSets;
  let rendered: BlockSqlFile[];

  try {
    rendered = renderBlocks(
      context.config.blockNames,
      await moduleLayoutFor(context.config, {
        names: context.config.blockNames,
        testsDir: context.config.sql.testsDir,
        readSets: skipped ? [] : readSets,
        entitlementsProvider: entitlementsModule(context),
        accessProvider: access.kind === "provider" ? access.access : undefined,
        permissionCatalog: permissionCatalogKeys(context),
      }),
    );
  } catch {
    // A config `upgrade` refuses (such as api-keys scopes "catalog" without
    // a catalog) has no files to compare; `upgrade` reports why.
    return [];
  }

  const files = rendered.filter(
    (file) => !(skipped && file.module === "read-sets"),
  );

  if (workflowOf(context) === "migrations") {
    const latest = await latestMigration(context.config, MODULES_SUFFIX);
    const versions = migrationModules(latest?.text ?? "");

    const path =
      latest?.path ??
      `${migrationsDir(context.config)}/<stamp>${MODULES_SUFFIX}`;

    return Promise.all(
      files.map(async (file): Promise<BlockSqlFileState> => {
        if (file.kind === "test") {
          return fileState(context, file);
        }

        const installed = versions.get(file.instance ?? file.module);

        return {
          file,
          path,
          installed,
          current:
            latest === undefined
              ? undefined
              : migrationHolds(latest.text, file.contents)
                ? file.contents
                : latest.text,
          behind:
            file.kind === "schema" &&
            installed !== undefined &&
            installed < (moduleFileVersion(file.contents)?.version ?? 1),
        };
      }),
    );
  }

  return Promise.all(files.map((file) => fileState(context, file)));
}

async function fileState(
  context: DoctorContext,
  file: BlockSqlFile,
): Promise<BlockSqlFileState> {
  const current = await readFile(
    resolve(context.config.root, file.path),
    "utf-8",
  ).catch(() => undefined);

  const installed =
    current === undefined
      ? undefined
      : (moduleFileVersion(current)?.version ?? 1);

  return {
    file,
    path: file.path,
    current,
    installed,
    behind:
      installed !== undefined &&
      installed < (moduleFileVersion(file.contents)?.version ?? 1),
  };
}
