import type { AnyBlocksConfig } from "../config/blocks.ts";
import type { BlockSqlContext } from "./context.ts";
import type { BlockSqlLayout } from "./module-types.ts";

import { moduleContext } from "./module-context.ts";
import { SQL_MODULES } from "./registry.ts";
import { moduleBody } from "./render.ts";
import {
  declaredColumnTypes,
  declaredEnums,
  declaredTableColumns,
  qualified,
} from "./schema-scan.ts";
import { computedWrites } from "./text-writes.ts";

/**
 * A table of the app's that a module reads and writes (in adopt mode, or one
 * `ownTables` lists), with the columns it uses.
 */
export interface AdoptedTable {
  readonly module: string;
  readonly logical: string;
  readonly schema: string;
  readonly table: string;
  /** Logical column to the physical column the module's SQL names. */
  readonly columns: Readonly<Record<string, string>>;
  /**
   * Logical text columns a module writes a computed value into without
   * `ctx.cast`, so the app's column must take a text value: an enum there
   * fails. Columns written only with string literals are left out.
   */
  readonly textColumns: readonly string[];
}

const rendered = (render: () => string | undefined): string => {
  try {
    return render() ?? "";
  } catch {
    return "";
  }
};

let defaults: ReadonlyMap<string, ReadonlySet<string>> | undefined;

function defaultWrites(): ReadonlyMap<string, ReadonlySet<string>> {
  defaults ??= computedWrites(
    Object.values(SQL_MODULES)
      .map((module) => rendered(() => module.sql))
      .join("\n"),
  );

  return defaults;
}

function configuredWrites(
  modules: AnyBlocksConfig,
  ownTables: Readonly<Record<string, string>> | undefined,
): ReadonlyMap<string, ReadonlySet<string>> {
  return computedWrites(
    Object.keys(modules)
      .map((name) =>
        rendered(() =>
          moduleBody(name, {
            modules,
            ...(ownTables === undefined ? {} : { ownTables }),
          }),
        ),
      )
      .join("\n"),
  );
}

const managedText = new Map<
  string,
  ReadonlyMap<string, readonly (readonly [string, boolean])[]>
>();

function managedTextColumns(
  module: string,
): ReadonlyMap<string, readonly (readonly [string, boolean])[]> {
  const cached = managedText.get(module);

  if (cached !== undefined) {
    return cached;
  }

  const definition = SQL_MODULES[module];
  const ctx = moduleContext(module, {});
  const tables = new Map<string, readonly (readonly [string, boolean])[]>();

  if (definition?.names !== undefined) {
    const types = declaredColumnTypes(
      [{ text: rendered(() => definition.sql) }],
      [ctx.schemaName],
    );

    for (const [logical, spec] of Object.entries(definition.names.tables)) {
      const { schema, name } = ctx.tableName(logical);
      const declared = types.get(`${schema}.${name}`);
      const written = defaultWrites().get(`${schema}.${name}`);

      if (declared === undefined) {
        continue;
      }

      tables.set(
        logical,
        Object.entries(spec.columns)
          .filter(
            ([column, physical]) =>
              declared.get(physical) === "text" &&
              spec.typed?.includes(column) !== true,
          )
          .map(([column, physical]) => [
            column,
            written?.has(physical) === true,
          ]),
      );
    }
  }

  managedText.set(module, tables);

  return tables;
}

/**
 * A module's context. An adopted module's context throws on what it refuses; a
 * managed one's problems are reported when it renders, so it has none here.
 */
function contextOf(
  name: string,
  layout: BlockSqlLayout & { readonly modules: AnyBlocksConfig },
  adopted: boolean,
): BlockSqlContext | undefined {
  const installed = Object.keys(layout.modules);

  if (adopted) {
    return moduleContext(name, layout, installed);
  }

  try {
    return moduleContext(name, layout, installed);
  } catch {
    return undefined;
  }
}

/**
 * Every table of the app's that the modules in `modules` use, in adopt mode or
 * because `ownTables` lists it, with the columns their SQL names: mapped to
 * `null` and unused optional columns are left out.
 */
export function adoptedTables(
  modules: AnyBlocksConfig,
  ownTables?: Readonly<Record<string, string>>,
): readonly AdoptedTable[] {
  const tables: AdoptedTable[] = [];
  const layout = { modules, ...(ownTables === undefined ? {} : { ownTables }) };

  const contexts = Object.keys(modules).flatMap((name) => {
    const mode = modules[name]?.mode ?? "managed";

    if (
      SQL_MODULES[name]?.names?.tables === undefined ||
      mode === "custom" ||
      (mode === "managed" && ownTables === undefined)
    ) {
      return [];
    }

    const ctx = contextOf(name, layout, mode === "adopt");

    return ctx !== undefined && ctx.appOwned.length > 0
      ? [[name, ctx] as const]
      : [];
  });

  const written =
    contexts.length > 0
      ? configuredWrites(modules, ownTables)
      : new Map<string, ReadonlySet<string>>();

  for (const [name, ctx] of contexts) {
    const spec = SQL_MODULES[name]!.names!.tables;

    const unchecked = ctx.manages
      ? {}
      : (SQL_MODULES[name]?.adoptOptional?.(ctx) ?? {});

    const text = managedTextColumns(name);

    for (const [logical, table] of Object.entries(spec)) {
      if (!ctx.appOwned.includes(logical)) {
        continue;
      }

      const columns: Record<string, string> = {};

      for (const [column, physical] of Object.entries(table.columns)) {
        if (!ctx.has(logical, column) || unchecked[logical]?.includes(column)) {
          continue;
        }

        columns[column] = ctx.config.columns[logical]?.[column] ?? physical;
      }

      const { schema, name: tableName } = ctx.tableName(logical);

      tables.push({
        module: name,
        logical,
        schema,
        table: tableName,
        columns,
        textColumns: (text.get(logical) ?? [])
          .filter(
            ([column, byDefault]) =>
              column in columns &&
              (byDefault ||
                written.get(`${schema}.${tableName}`)?.has(columns[column]!) ===
                  true),
          )
          .map(([column]) => column),
      });
    }

    const subjects = ctx.manages
      ? []
      : (SQL_MODULES[name]?.adoptSubjectTables?.(ctx) ?? []);

    for (const extra of subjects) {
      const columns: Record<string, string> = {};

      for (const [column, physical] of Object.entries(extra.columns)) {
        if (physical !== null) {
          columns[column] = physical;
        }
      }

      tables.push({
        module: name,
        logical: extra.logical,
        schema: extra.schema,
        table: extra.table,
        columns,
        textColumns: [],
      });
    }
  }

  return tables;
}

/**
 * Adopt-mode modules that default an optional column to its physical name while
 * the adopted `create table` has no such column. `upgrade` refuses those
 * configs so `has()` does not treat a missing column as present.
 */
export function adoptedColumnProblems(
  modules: AnyBlocksConfig,
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
  ownTables?: Readonly<Record<string, string>>,
): readonly string[] {
  const declared = declaredTableColumns(files, schemas);
  const problems: string[] = [];

  for (const name of Object.keys(modules)) {
    if ((modules[name]?.mode ?? "managed") !== "adopt") {
      continue;
    }

    const spec = SQL_MODULES[name]?.names?.tables;

    if (spec === undefined) {
      continue;
    }

    const ctx = moduleContext(name, { modules }, Object.keys(modules));
    const unchecked = SQL_MODULES[name]?.adoptOptional?.(ctx) ?? {};

    for (const [logical, table] of Object.entries(spec)) {
      if (
        !ctx.hasTable(logical) ||
        (table.adoptOnlyWhenMapped === true &&
          ctx.config.tables[logical] === undefined)
      ) {
        continue;
      }

      const { schema, name: tableName } = ctx.tableName(logical);
      const columns = declared.get(`${schema}.${tableName}`);

      if (columns === undefined) {
        continue;
      }

      for (const [column, physical] of Object.entries(table.columns)) {
        if (
          !table.optional?.includes(column) ||
          !ctx.has(logical, column) ||
          unchecked[logical]?.includes(column)
        ) {
          continue;
        }

        const mapped = ctx.config.columns[logical]?.[column];
        const used = mapped ?? physical;

        if (columns.has(used)) {
          continue;
        }

        problems.push(
          `blocks.${name} is in adopt mode and uses ${schema}.${tableName}.${used} (${logical}.${column}), but that column is not in the table. Map blocks.${name}.columns.${logical}.${column} to null, or add the column.`,
        );
      }
    }

    for (const extra of SQL_MODULES[name]?.adoptSubjectTables?.(ctx) ?? []) {
      const columns = declared.get(`${extra.schema}.${extra.table}`);

      if (columns === undefined) {
        continue;
      }

      for (const [column, physical] of Object.entries(extra.columns)) {
        if (physical === null || columns.has(physical)) {
          continue;
        }

        problems.push(
          `blocks.${name} is in adopt mode and uses ${extra.schema}.${extra.table}.${physical} (${extra.logical}.${column}), but that column is not in the table. Set blocks.${name}.on so that column matches the table, or add the column.`,
        );
      }
    }
  }

  return [
    ...problems,
    ...enumColumnProblems(modules, files, schemas, ownTables),
  ];
}

function enumColumnProblems(
  modules: AnyBlocksConfig,
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
  ownTables: Readonly<Record<string, string>> | undefined,
): readonly string[] {
  const enums = declaredEnums(files);

  if (enums.size === 0) {
    return [];
  }

  const types = declaredColumnTypes(files, schemas);

  return adoptedTables(modules, ownTables).flatMap((table) => {
    const declared = types.get(`${table.schema}.${table.table}`);

    if (declared === undefined) {
      return [];
    }

    return table.textColumns.flatMap((logical) => {
      const column = table.columns[logical];
      const type = column === undefined ? undefined : declared.get(column);

      if (
        column === undefined ||
        type === undefined ||
        type.endsWith("]") ||
        !enums.has(qualified(type))
      ) {
        return [];
      }

      return [enumColumnProblem(table, logical, column, qualified(type))];
    });
  });
}

function enumColumnProblem(
  table: AdoptedTable,
  logical: string,
  column: string,
  type: string,
): string {
  return `blocks.${table.module} writes text into ${table.schema}.${table.table}.${column} (${table.logical}.${logical}), which is the enum ${type}. Postgres does not cast text to an enum, so the module's functions fail. Change the column to text with a check constraint on its values.`;
}
