import { posix, resolve } from "node:path";

import type { OwnedColumn } from "../sql/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { ownedColumns, renderBlocks } from "../sql/index.ts";
import { schemasDirOf } from "./codemod-extra-columns.ts";
import { layoutFor } from "./sql/providers.ts";

/**
 * The files that declare `columns` in the app's own schema: one
 * `<table>.block-columns.sql` per table, next to the schema files. The
 * statements are the blocks' own `add column if not exists`, so they change
 * nothing in a database that already has the columns.
 */
export function ownedColumnFiles(
  columns: readonly OwnedColumn[],
  schemasDir: string,
  exists: (path: string) => boolean = () => false,
): readonly PlannedFile[] {
  const byTable = new Map<string, OwnedColumn[]>();

  for (const column of columns) {
    byTable.set(column.table, [...(byTable.get(column.table) ?? []), column]);
  }

  return [...byTable].flatMap(([table, entries]): PlannedFile[] => {
    const path = posix.join(
      schemasDir,
      `${table.slice(table.indexOf(".") + 1)}.block-columns.sql`,
    );

    if (exists(path)) {
      return [];
    }

    return [
      {
        path,
        contents: `-- Columns the blocks add to ${table}, declared in your schema.\n-- better-supabase upgrade never rewrites this file.\n\n${entries.map((entry) => entry.statement).join("\n")}\n`,
        policy: "create",
      },
    ];
  });
}

/**
 * The `owned-columns` codemod: declare, in the app's schema files, the columns
 * the blocks add to tables the app creates (ADR 0325).
 */
export function ownedColumnsCodemod(): Codemod {
  return {
    name: "owned-columns",
    description:
      "Declare the columns blocks add to your own tables in your schema files",
    project: async (project: CodemodProject) => {
      const { config } = project;

      const app = project.sql.filter(
        (file) =>
          !/[\\/]migrations[\\/]/.test(file.path) &&
          !/(?:^|[\\/])900_better_supabase_/.test(file.path) &&
          !/@bsb-block\b/.test(file.text),
      );

      let columns: readonly OwnedColumn[] = [];

      try {
        const layout = {
          ...(await layoutFor(config, {}, config.blockNames)),
          keepUndeclaredColumns: true,
        };

        columns = ownedColumns(
          renderBlocks(config.blockNames, layout).map((file) => ({
            contents: file.contents,
          })),
          app,
          config.schemas,
        );
      } catch (error) {
        return {
          files: [],
          review: [
            {
              message: `The blocks don't render for this project yet (${error instanceof Error ? error.message : String(error)}), so no columns were found. Run \`better-supabase upgrade\` first and fix what it reports.`,
            },
          ],
        };
      }

      return {
        files: ownedColumnFiles(
          columns,
          resolve(config.root, schemasDirOf(config.sql.dir)),
        ),
        review: [],
      };
    },
  };
}
