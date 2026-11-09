import { posix, resolve } from "node:path";

import type { ResolvedConfig } from "../config/index.ts";
import type { OwnedColumn } from "../sql/index.ts";
import type { Codemod, CodemodProject } from "./codemod.ts";
import type { PlannedFile } from "./core/files.ts";

import { ownedColumns, renderBlocks, SQL_MODULES } from "../sql/index.ts";
import { schemasDirOf } from "./codemod-extra-columns.ts";
import { columnPins, pinReview } from "./codemod-naming-pins.ts";
import { NAMING_RENAMES } from "./codemod-naming.ts";
import { ownLayout, snapshotColumnTypes } from "./sql-layout.ts";
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

interface OptionalColumn {
  readonly block: string;
  readonly table: string;
  readonly logical: string;
}

/**
 * Optional block columns by `schema.table.column`. A column the config maps to
 * `null` is already opted out.
 */
function optionalColumns(config: ResolvedConfig): Map<string, OptionalColumn> {
  const found = new Map<string, OptionalColumn>();
  const schema = config.sql.blockDefaults?.schema ?? "better_supabase";

  const consider = (
    key: string,
    module: string,
    block: {
      readonly schema?: string | undefined;
      readonly tables?:
        | Readonly<Record<string, string | null | undefined>>
        | undefined;
      readonly columns?:
        | Readonly<
            Record<
              string,
              Readonly<Record<string, string | null | undefined>> | undefined
            >
          >
        | undefined;
    },
  ): void => {
    const names = SQL_MODULES[module]?.names;

    if (names === undefined) {
      return;
    }

    const blockSchema = block.schema ?? schema;

    for (const [logical, spec] of Object.entries(names.tables)) {
      for (const column of spec.optional ?? []) {
        const configured = block.columns?.[logical]?.[column];

        if (configured === null) {
          continue;
        }

        const physicalColumn =
          typeof configured === "string" ? configured : spec.columns[column];

        if (physicalColumn === undefined) {
          continue;
        }

        const mapped = block.tables?.[logical];

        const physicalTable =
          typeof mapped === "string"
            ? mapped.includes(".")
              ? mapped
              : `${blockSchema}.${mapped}`
            : `${blockSchema}.${spec.name}`;

        found.set(`${physicalTable}.${physicalColumn}`, {
          block: key,
          table: logical,
          logical: column,
        });
      }
    }
  };

  for (const [name, block] of Object.entries(config.blocks)) {
    if (block !== undefined) {
      consider(name, name, block);
    }
  }

  for (const instance of Object.values(config.instances)) {
    consider(instance.name, instance.block, instance.config);
  }

  return found;
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
      const review: { message: string }[] = [];

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

        const own = await ownLayout(config);

        const report = columnPins(
          config,
          NAMING_RENAMES,
          own.ownTables ?? {},
          own.ownColumns ?? {},
        );

        const present = await snapshotColumnTypes(
          config,
          columns.map((column) => column.table),
        );

        const blocked = new Map<string, (typeof report.pins)[number]>();

        for (const pin of report.pins) {
          const next =
            SQL_MODULES[pin.module]?.names?.tables[pin.table]?.columns[
              pin.column
            ];

          if (next !== undefined && next !== pin.name) {
            blocked.set(`${pin.physical}.${next}`, pin);
          }
        }

        const optional = optionalColumns(config);
        const kept: OwnedColumn[] = [];

        review.push(...report.review.map((message) => ({ message })));

        for (const column of columns) {
          const pin = blocked.get(`${column.table}.${column.column}`);

          if (pin !== undefined) {
            review.push({ message: pinReview(pin) });
            continue;
          }

          const choice = optional.get(`${column.table}.${column.column}`);

          if (
            choice !== undefined &&
            present.get(column.table)?.has(column.column) !== true
          ) {
            review.push({
              message: `blocks.${choice.block}.columns.${choice.table}.${choice.logical} is optional, and the database or snapshot has no "${column.column}" column on ${column.table}. Set it to null to keep the feature off.`,
            });
            continue;
          }

          kept.push(column);
        }

        columns = kept;
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
        review,
      };
    },
  };
}
