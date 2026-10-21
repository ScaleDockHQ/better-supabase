import {
  APP_ROLLUP_AGGREGATES,
  type AppColumnType,
  type AppLookupConfig,
  type AppRollupAggregate,
  type AppRollupConfig,
  type AppTableConfig,
  type AppTablesConfig,
} from "./types/app-tables.ts";

const IDENT = /^[a-z][a-z0-9_]{0,62}$/;

/** Rollups and lookups together, per table. */
const MAX_COMPUTED = 50;

const ROLLUP_KEYS: ReadonlySet<string> = new Set([
  "table",
  "via",
  "aggregate",
  "column",
  "where",
]);

const WHERE_KEYS: ReadonlySet<string> = new Set(["column", "equals"]);
const LOOKUP_KEYS: ReadonlySet<string> = new Set(["via", "column"]);
const AGGREGATES: ReadonlySet<string> = new Set(APP_ROLLUP_AGGREGATES);

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

type Json = Readonly<Record<string, unknown>>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isAggregate(value: unknown): value is AppRollupAggregate {
  return typeof value === "string" && AGGREGATES.has(value);
}

function checkKeys(
  where: string,
  value: Json,
  allowed: ReadonlySet<string>,
): void {
  for (const key of Object.keys(value)) {
    if (!allowed.has(key)) {
      throw new TypeError(
        `${where}: unknown key "${key}" (use ${[...allowed].join(", ")})`,
      );
    }
  }
}

/** The columns of `table` a rollup or lookup may read, with their types. */
function readable(table: AppTableConfig): ReadonlyMap<string, AppColumnType> {
  return new Map<string, AppColumnType>([
    ...Object.entries(table.columns ?? {}).map(
      ([name, column]): [string, AppColumnType] => [name, column.type],
    ),
    ...(table.timestamps === false
      ? []
      : ([
          ["created_at", "timestamptz"],
          ["updated_at", "timestamptz"],
        ] as const)),
  ]);
}

function listOf(names: Iterable<string>): string {
  const list = [...names].join(", ");

  return list === "" ? "none" : list;
}

/** The columns of `child` that reference the app table `parent`. */
function referencesTo(child: AppTableConfig, parent: string): string[] {
  return Object.entries(child.columns ?? {})
    .filter(
      ([, column]) =>
        column.references !== undefined &&
        !("block" in column.references) &&
        column.references.table === parent,
    )
    .map(([name]) => name);
}

function whereOf(
  where: string,
  value: unknown,
  child: string,
  table: AppTableConfig,
): AppRollupConfig["where"] {
  if (value === undefined) {
    return undefined;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be { column, equals }`);
  }

  checkKeys(where, value, WHERE_KEYS);
  const { column, equals } = value;

  const selects = Object.entries(table.columns ?? {}).filter(
    ([, each]) => each.type === "text" && each.options !== undefined,
  );

  const found = selects.find(([name]) => name === column)?.[1];

  if (typeof column !== "string" || found?.options === undefined) {
    throw new TypeError(
      `${where}.column must name a select column of ${child} (${listOf(selects.map(([name]) => name))})`,
    );
  }

  if (typeof equals !== "string" || !found.options.includes(equals)) {
    throw new TypeError(
      `${where}.equals must be an option of ${child}.${column} (${listOf(found.options)})`,
    );
  }

  return { column, equals };
}

function rollupOf(
  where: string,
  value: unknown,
  parent: string,
  tables: AppTablesConfig,
): AppRollupConfig {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, ROLLUP_KEYS);
  const { table, via, aggregate, column } = value;
  const child = typeof table === "string" ? tables[table] : undefined;

  if (typeof table !== "string" || child === undefined) {
    throw new TypeError(
      `${where}.table must name an app table (${listOf(Object.keys(tables))})`,
    );
  }

  const vias = referencesTo(child, parent);

  if (typeof via !== "string" || !vias.includes(via)) {
    throw new TypeError(
      `${where}.via must name a column of ${table} that references ${parent} (${listOf(vias)})`,
    );
  }

  if (!isAggregate(aggregate)) {
    throw new TypeError(
      `${where}.aggregate must be one of ${APP_ROLLUP_AGGREGATES.join(", ")}`,
    );
  }

  const filter = whereOf(`${where}.where`, value["where"], table, child);
  const base = { table, via, aggregate, ...(filter ? { where: filter } : {}) };

  if (aggregate === "count") {
    if (column !== undefined) {
      throw new TypeError(`${where}.column: count counts rows; drop column`);
    }

    return base;
  }

  const fits = aggregate === "sum" || aggregate === "avg" ? NUMBERS : ORDERED;

  const candidates = [...readable(child)]
    .filter(([, type]) => fits.has(type))
    .map(([name]) => name);

  if (typeof column !== "string" || !candidates.includes(column)) {
    throw new TypeError(
      `${where}.column: ${aggregate} needs a ${fits === NUMBERS ? "number" : "number, date, time or text"} column of ${table} (${listOf(candidates)})`,
    );
  }

  return { ...base, column };
}

function lookupOf(
  where: string,
  value: unknown,
  name: string,
  tables: AppTablesConfig,
): AppLookupConfig {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, LOOKUP_KEYS);
  const { via, column } = value;
  const own = tables[name]?.columns ?? {};

  const vias = Object.entries(own).filter(
    ([, each]) =>
      each.references !== undefined &&
      !("block" in each.references) &&
      Object.hasOwn(tables, each.references.table),
  );

  const reference = vias.find(([each]) => each === via)?.[1].references;

  if (
    typeof via !== "string" ||
    reference === undefined ||
    "block" in reference
  ) {
    throw new TypeError(
      `${where}.via must name a column of ${name} that references another app table (${listOf(vias.map(([each]) => each))})`,
    );
  }

  const target = tables[reference.table];
  const columns = target === undefined ? new Map() : readable(target);

  if (typeof column !== "string" || !columns.has(column)) {
    throw new TypeError(
      `${where}.column must name a column of ${reference.table} (${listOf(columns.keys())})`,
    );
  }

  return { via, column };
}

function entriesOf(where: string, value: unknown): [string, unknown][] {
  if (value === undefined) {
    return [];
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object keyed by column name`);
  }

  return Object.entries(value);
}

/**
 * The `rollups` and `lookups` of the app table `name`, checked against every
 * resolved app table. `taken` holds the columns the table already has, which a
 * computed column may not reuse.
 */
export function computedOf(
  where: string,
  value: unknown,
  name: string,
  tables: AppTablesConfig,
  taken: ReadonlySet<string>,
): Pick<AppTableConfig, "lookups" | "rollups"> {
  if (!isObject(value)) {
    return {};
  }

  const rollups = entriesOf(`${where}.rollups`, value["rollups"]);
  const lookups = entriesOf(`${where}.lookups`, value["lookups"]);

  if (rollups.length + lookups.length > MAX_COMPUTED) {
    throw new TypeError(
      `${where}: at most ${String(MAX_COMPUTED)} rollups and lookups together`,
    );
  }

  const used = new Set(taken);

  const named = (key: "lookups" | "rollups", column: string): string => {
    const at = `${where}.${key}.${column}`;

    if (!IDENT.test(column)) {
      throw new TypeError(
        `${at}: "${column}" is not a lower snake identifier (a-z, 0-9 and _, starting with a letter)`,
      );
    }

    if (used.has(column)) {
      throw new TypeError(
        `${at}: "${column}" is already a column of ${name}; choose another name`,
      );
    }

    used.add(column);

    return at;
  };

  const resolvedRollups = rollups.map(
    ([column, rollup]): [string, AppRollupConfig] => [
      column,
      rollupOf(named("rollups", column), rollup, name, tables),
    ],
  );

  const resolvedLookups = lookups.map(
    ([column, lookup]): [string, AppLookupConfig] => [
      column,
      lookupOf(named("lookups", column), lookup, name, tables),
    ],
  );

  return {
    ...(value["rollups"] === undefined
      ? {}
      : { rollups: Object.fromEntries(resolvedRollups) }),
    ...(value["lookups"] === undefined
      ? {}
      : { lookups: Object.fromEntries(resolvedLookups) }),
  };
}

/** Whether a table has a rollup or a lookup, and so a `<table>_view`. */
export function hasComputed(table: AppTableConfig): boolean {
  return (
    Object.keys(table.rollups ?? {}).length > 0 ||
    Object.keys(table.lookups ?? {}).length > 0
  );
}
