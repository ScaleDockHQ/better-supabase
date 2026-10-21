import type { AppColumnType, AppTable } from "./design.ts";

/** The aggregates a rollup takes (`APP_ROLLUP_AGGREGATES`). */
export const ROLLUP_AGGREGATES = ["count", "sum", "min", "max", "avg"] as const;

export type RollupAggregate = (typeof ROLLUP_AGGREGATES)[number];

/** `appTables.<table>.rollups.<name>`; the shape of `AppRollupConfig`. */
export interface AppRollup {
  readonly table: string;
  readonly via: string;
  readonly aggregate: RollupAggregate;
  readonly column?: string;
  readonly where?: { readonly column: string; readonly equals: string };
}

/** `appTables.<table>.lookups.<name>`; the shape of `AppLookupConfig`. */
export interface AppLookup {
  readonly via: string;
  readonly column: string;
}

/** A rollup or lookup as a table node and the inspector list it. */
export interface ComputedRow {
  readonly name: string;
  readonly kind: "rollup" | "lookup";
  /** What it computes, such as `count of tasks where status = todo`. */
  readonly summary: string;
  /** The short form the node shows next to the name, such as `count`. */
  readonly label: string;
}

type Tables = Readonly<Record<string, AppTable>>;

const NUMBERS: ReadonlySet<AppColumnType> = new Set([
  "integer",
  "bigint",
  "numeric",
]);

const ORDERED: ReadonlySet<AppColumnType> = new Set([
  ...NUMBERS,
  "date",
  "timestamptz",
  "text",
]);

export function isRollupAggregate(value: unknown): value is RollupAggregate {
  return ROLLUP_AGGREGATES.some((each) => each === value);
}

/** The columns of `table` a rollup or lookup can read, with their types. */
export function readableColumns(
  table: AppTable,
): readonly (readonly [string, AppColumnType])[] {
  return [
    ...Object.entries(table.columns ?? {}).map(
      ([name, column]) => [name, column.type] as const,
    ),
    ...(table.timestamps === false
      ? []
      : ([
          ["created_at", "timestamptz"],
          ["updated_at", "timestamptz"],
        ] as const)),
  ];
}

/**
 * The columns `aggregate` can read: numbers for sum and avg, ordered types for
 * min and max, none for count.
 */
export function rollupColumns(
  child: AppTable,
  aggregate: RollupAggregate,
): readonly string[] {
  if (aggregate === "count") {
    return [];
  }

  const fits = aggregate === "sum" || aggregate === "avg" ? NUMBERS : ORDERED;

  return readableColumns(child)
    .filter(([, type]) => fits.has(type))
    .map(([name]) => name);
}

/** The select columns of `child` (text with options) a rollup can filter on. */
export function filterColumns(
  child: AppTable,
): readonly (readonly [string, readonly string[]])[] {
  return Object.entries(child.columns ?? {}).flatMap(([name, column]) =>
    column.type === "text" && column.options !== undefined
      ? [[name, column.options] as const]
      : [],
  );
}

/**
 * Each app table column that references `parent`, as `{ table, via }`: what a
 * rollup on `parent` can aggregate.
 */
export function rollupSources(
  tables: Tables,
  parent: string,
): readonly { readonly table: string; readonly via: string }[] {
  return Object.entries(tables).flatMap(([table, config]) =>
    Object.entries(config.columns ?? {})
      .filter(
        ([, column]) =>
          column.references !== undefined &&
          column.references.block === undefined &&
          column.references.table === parent,
      )
      .map(([via]) => ({ table, via })),
  );
}

/**
 * Each column of `name` that references another app table, with that table:
 * what a lookup can follow.
 */
export function lookupSources(
  tables: Tables,
  name: string,
): readonly { readonly via: string; readonly target: string }[] {
  return Object.entries(tables[name]?.columns ?? {}).flatMap(([via, column]) =>
    column.references !== undefined &&
    column.references.block === undefined &&
    Object.hasOwn(tables, column.references.table)
      ? [{ via, target: column.references.table }]
      : [],
  );
}

function rollupValid(
  tables: Tables,
  parent: string,
  rollup: AppRollup,
): boolean {
  const child = tables[rollup.table];

  if (
    child === undefined ||
    !rollupSources(tables, parent).some(
      (each) => each.table === rollup.table && each.via === rollup.via,
    )
  ) {
    return false;
  }

  const column =
    rollup.aggregate === "count"
      ? rollup.column === undefined
      : rollup.column !== undefined &&
        rollupColumns(child, rollup.aggregate).includes(rollup.column);

  const where =
    rollup.where === undefined ||
    filterColumns(child).some(
      ([name, options]) =>
        name === rollup.where?.column && options.includes(rollup.where.equals),
    );

  return column && where;
}

function lookupValid(tables: Tables, name: string, lookup: AppLookup): boolean {
  const source = lookupSources(tables, name).find(
    (each) => each.via === lookup.via,
  );

  const target = source === undefined ? undefined : tables[source.target];

  return (
    target !== undefined &&
    readableColumns(target).some(([column]) => column === lookup.column)
  );
}

function kept<T>(
  record: Readonly<Record<string, T>> | undefined,
  keep: (name: string, value: T) => boolean,
): Readonly<Record<string, T>> | undefined {
  if (record === undefined) {
    return undefined;
  }

  const entries = Object.entries(record).filter(([name, value]) =>
    keep(name, value),
  );

  return entries.length === 0 ? undefined : Object.fromEntries(entries);
}

type Rollups = Readonly<Record<string, AppRollup>>;

type Lookups = Readonly<Record<string, AppLookup>>;

type DraftTable = { -readonly [K in keyof AppTable]: AppTable[K] };

export type DraftRollup = { -readonly [K in keyof AppRollup]: AppRollup[K] };

/** `table` with its rollups and lookups replaced, leaving out an empty set. */
function withComputed(
  table: AppTable,
  rollups: Rollups | undefined,
  lookups: Lookups | undefined,
): AppTable {
  const { rollups: _rollups, lookups: _lookups, ...rest } = table;
  const next: DraftTable = { ...rest };

  if (rollups !== undefined && Object.keys(rollups).length > 0) {
    next.rollups = rollups;
  }

  if (lookups !== undefined && Object.keys(lookups).length > 0) {
    next.lookups = lookups;
  }

  return next;
}

/**
 * `table` with a rollup or lookup set under `name`, replacing `previous` in its
 * place.
 */
export function tableWithComputed(
  table: AppTable,
  name: string,
  computed: { readonly rollup: AppRollup } | { readonly lookup: AppLookup },
  previous: string,
): AppTable {
  const placed = <T>(
    record: Readonly<Record<string, T>> | undefined,
    value: T,
  ): Readonly<Record<string, T>> => {
    const entries = Object.entries(record ?? {});
    const added: [string, T] = [name, value];

    return Object.fromEntries(
      entries.some(([each]) => each === previous)
        ? entries.map(([each, config]): [string, T] =>
            each === previous ? added : [each, config],
          )
        : [...entries, added],
    );
  };

  return "rollup" in computed
    ? withComputed(table, placed(table.rollups, computed.rollup), table.lookups)
    : withComputed(
        table,
        table.rollups,
        placed(table.lookups, computed.lookup),
      );
}

/** `table` without the rollup or lookup `name`. */
export function tableWithoutComputed(table: AppTable, name: string): AppTable {
  return withComputed(
    table,
    kept(table.rollups, (each) => each !== name),
    kept(table.lookups, (each) => each !== name),
  );
}

/**
 * The tables with every rollup and lookup that no longer fits dropped: one
 * whose table, link or column was deleted or retyped, or whose name a column
 * now uses. `sql sync` would refuse them, and the design code would not
 * encode.
 */
export function prunedComputed(tables: Tables): Tables {
  return Object.fromEntries(
    Object.entries(tables).map(([name, table]) => {
      const own = new Set(Object.keys(table.columns ?? {}));

      const rollups = kept(
        table.rollups,
        (column, rollup) =>
          !own.has(column) && rollupValid(tables, name, rollup),
      );

      const lookups = kept(
        table.lookups,
        (column, lookup) =>
          !own.has(column) &&
          rollups?.[column] === undefined &&
          lookupValid(tables, name, lookup),
      );

      return [name, withComputed(table, rollups, lookups)];
    }),
  );
}

/** The rollups that aggregate `from`, pointed at `to`. */
export function computedTableRenamed(
  tables: Tables,
  from: string,
  to: string,
): Tables {
  return Object.fromEntries(
    Object.entries(tables).map(([name, table]) => [
      name,
      table.rollups === undefined
        ? table
        : {
            ...table,
            rollups: Object.fromEntries(
              Object.entries(table.rollups).map(([column, rollup]) => [
                column,
                rollup.table === from ? { ...rollup, table: to } : rollup,
              ]),
            ),
          },
    ]),
  );
}

/**
 * The rollup fitted to a new source or aggregate: a column the aggregate can
 * read, and a filter the child still has.
 */
export function fittedRollup(tables: Tables, rollup: AppRollup): AppRollup {
  const child = tables[rollup.table] ?? {};
  const columns = rollupColumns(child, rollup.aggregate);

  const aggregate: RollupAggregate =
    rollup.aggregate !== "count" && columns.length === 0
      ? "count"
      : rollup.aggregate;

  const column =
    aggregate === "count"
      ? undefined
      : rollup.column !== undefined && columns.includes(rollup.column)
        ? rollup.column
        : columns[0];

  const where =
    rollup.where !== undefined &&
    filterColumns(child).some(
      ([name, options]) =>
        name === rollup.where?.column && options.includes(rollup.where.equals),
    )
      ? rollup.where
      : undefined;

  const next: DraftRollup = { table: rollup.table, via: rollup.via, aggregate };

  if (column !== undefined) {
    next.column = column;
  }

  if (where !== undefined) {
    next.where = where;
  }

  return next;
}

function rollupRenamed(
  rollup: AppRollup,
  swap: (column: string) => string,
): AppRollup {
  const next: DraftRollup = { ...rollup, via: swap(rollup.via) };

  if (rollup.column !== undefined) {
    next.column = swap(rollup.column);
  }

  if (rollup.where !== undefined) {
    next.where = { ...rollup.where, column: swap(rollup.where.column) };
  }

  return next;
}

/**
 * Every rollup and lookup that reads `table.from`, reading `table.to`. The
 * tables already have the column renamed, so a lookup finds its target through
 * the renamed link.
 */
export function computedColumnRenamed(
  tables: Tables,
  table: string,
  from: string,
  to: string,
): Tables {
  const swap = (column: string): string => (column === from ? to : column);

  const lookupTarget = (owner: string, via: string): string | undefined => {
    const reference = tables[owner]?.columns?.[via]?.references;

    return reference?.block === undefined ? reference?.table : undefined;
  };

  return Object.fromEntries(
    Object.entries(tables).map(([name, config]) => {
      const rollups =
        config.rollups === undefined
          ? undefined
          : Object.fromEntries(
              Object.entries(config.rollups).map(([column, rollup]) => [
                column,
                rollup.table === table ? rollupRenamed(rollup, swap) : rollup,
              ]),
            );

      const lookups =
        config.lookups === undefined
          ? undefined
          : Object.fromEntries(
              Object.entries(config.lookups).map(([column, lookup]) => {
                const via = name === table ? swap(lookup.via) : lookup.via;

                return [
                  column,
                  {
                    via,
                    column:
                      lookupTarget(name, via) === table
                        ? swap(lookup.column)
                        : lookup.column,
                  },
                ];
              }),
            );

      return [name, withComputed(config, rollups, lookups)];
    }),
  );
}

function rollupSummary(rollup: AppRollup): string {
  const what =
    rollup.aggregate === "count"
      ? `count of ${rollup.table}`
      : `${rollup.aggregate} of ${rollup.table}.${rollup.column ?? ""}`;

  return rollup.where === undefined
    ? what
    : `${what} where ${rollup.where.column} = ${rollup.where.equals}`;
}

/** The rollups and lookups of an app table, in the view's column order. */
export function computedRows(table: AppTable): readonly ComputedRow[] {
  return [
    ...Object.entries(table.rollups ?? {}).map(
      ([name, rollup]): ComputedRow => ({
        name,
        kind: "rollup",
        summary: rollupSummary(rollup),
        label: rollup.aggregate,
      }),
    ),
    ...Object.entries(table.lookups ?? {}).map(
      ([name, lookup]): ComputedRow => {
        const target =
          table.columns?.[lookup.via]?.references?.table ?? lookup.via;

        return {
          name,
          kind: "lookup",
          summary: `${target}.${lookup.column} through ${lookup.via}`,
          label: "lookup",
        };
      },
    ),
  ];
}
