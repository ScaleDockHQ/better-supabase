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
 * A table of the app's that a module reads and writes (one `ownTables` lists,
 * or a subject table it writes columns of), with the columns it uses.
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

/** Per logical table, the columns the module's configuration doesn't use. */
function unusedColumns(
  name: string,
  ctx: BlockSqlContext,
): Readonly<Record<string, readonly string[]>> {
  return Object.fromEntries(
    Object.entries(SQL_MODULES[name]?.names?.tables ?? {}).map(
      ([logical, table]) => [logical, table.app?.unused?.(ctx) ?? []],
    ),
  );
}

/**
 * A module's context, or `undefined` when it refuses the config: rendering
 * reports that, so it has no tables here.
 */
function contextOf(
  name: string,
  layout: BlockSqlLayout & { readonly modules: AnyBlocksConfig },
): BlockSqlContext | undefined {
  try {
    return moduleContext(name, layout, Object.keys(layout.modules));
  } catch {
    return undefined;
  }
}

/**
 * Every table of the app's that the modules in `modules` use, because
 * `ownTables` lists it or `blocks.<name>.on` names it, with the columns their
 * SQL names: mapped to `null` and unused optional columns are left out.
 */
export function adoptedTables(
  modules: AnyBlocksConfig,
  ownTables?: Readonly<Record<string, string>>,
): readonly AdoptedTable[] {
  const tables: AdoptedTable[] = [];
  const layout = { modules, ...(ownTables === undefined ? {} : { ownTables }) };

  const contexts = Object.keys(modules).flatMap((name) => {
    const mode = modules[name]?.mode ?? "managed";

    if (SQL_MODULES[name]?.names?.tables === undefined || mode === "custom") {
      return [];
    }

    const ctx = contextOf(name, layout);

    return ctx !== undefined &&
      (ctx.appOwned.length > 0 ||
        (SQL_MODULES[name].appSubjectTables?.(ctx).length ?? 0) > 0)
      ? [[name, ctx] as const]
      : [];
  });

  const written =
    contexts.length > 0
      ? configuredWrites(modules, ownTables)
      : new Map<string, ReadonlySet<string>>();

  for (const [name, ctx] of contexts) {
    const spec = SQL_MODULES[name]!.names!.tables;

    const unchecked = unusedColumns(name, ctx);

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

    const subjects = SQL_MODULES[name]?.appSubjectTables?.(ctx) ?? [];

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
 * The columns the modules write on the app's other tables (`appSubjectTables`,
 * such as a tag link table) that those tables lack, and the enum columns they
 * write as text. `upgrade` refuses those configs. A column missing from a
 * block's own logical table isn't one: the block adds it.
 */
export function adoptedColumnProblems(
  modules: AnyBlocksConfig,
  files: readonly { readonly text: string }[],
  schemas: readonly string[],
  ownTables?: Readonly<Record<string, string>>,
): readonly string[] {
  const declared = declaredTableColumns(files, schemas);

  const problems = adoptedTables(modules, ownTables).flatMap((table) => {
    const columns = declared.get(`${table.schema}.${table.table}`);

    if (
      columns === undefined ||
      SQL_MODULES[table.module]?.names?.tables[table.logical] !== undefined
    ) {
      return [];
    }

    return Object.entries(table.columns)
      .filter(([, physical]) => !columns.has(physical))
      .map(
        ([column, physical]) =>
          `blocks.${table.module} uses ${table.schema}.${table.table}.${physical} (${table.logical}.${column}), but that column is not in the table. Set blocks.${table.module}.on so that column matches the table, or add the column.`,
      );
  });

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
