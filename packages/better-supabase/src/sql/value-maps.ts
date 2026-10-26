import { sqlIdent, sqlString } from "../core/template.ts";

/**
 * One column's `blocks.<name>.values.<table>.<column>`: each label the block
 * writes or compares, mapped to the value the app's column stores, to several
 * values (the first is written, every one reads as the label), or to `null` for
 * a label the app does not support.
 */
export type ValueMap = Readonly<
  Record<string, string | readonly string[] | null>
>;

/** `blocks.<name>.values`: logical table to logical column to its map. */
export type ValueMaps = Readonly<
  Record<string, Readonly<Record<string, ValueMap>>>
>;

const VALUE = /^[^\0]{1,200}$/u;

/**
 * `values`, checked against the module's tables: every table and column is one
 * the module declares and lists in `typed`, and every label and value is a
 * short string.
 */
export function checkedValueMaps(
  where: string,
  values: unknown,
  tables: Readonly<
    Record<
      string,
      {
        readonly columns: Readonly<Record<string, string>>;
        readonly typed?: readonly string[];
        readonly mappable?: readonly string[];
      }
    >
  >,
): ValueMaps {
  if (values === undefined) {
    return {};
  }

  const at = `${where}.values`;

  if (!isObject(values)) {
    throw new TypeError(`${at} must be an object of table to column to labels`);
  }

  const out: Record<string, Record<string, ValueMap>> = {};

  for (const [table, columns] of Object.entries(values)) {
    const known = tables[table];

    if (!known) {
      throw new TypeError(
        `${at}: unknown table "${table}". Tables: ${Object.keys(tables).join(", ") || "none"}`,
      );
    }

    if (!isObject(columns)) {
      throw new TypeError(
        `${at}.${table} must be an object of column to labels`,
      );
    }

    const checked: Record<string, ValueMap> = {};

    for (const [column, map] of Object.entries(columns)) {
      if (!(column in known.columns)) {
        throw new TypeError(
          `${at}.${table}: unknown column "${column}". Columns: ${Object.keys(known.columns).join(", ")}`,
        );
      }

      const mappable = [...(known.typed ?? []), ...(known.mappable ?? [])];

      if (!mappable.includes(column)) {
        throw new TypeError(
          `${at}.${table}.${column}: the block does not map values of this column. Columns with values: ${mappable.join(", ") || "none"}`,
        );
      }

      checked[column] = checkedMap(`${at}.${table}.${column}`, map);
    }

    out[table] = checked;
  }

  return out;
}

function checkedMap(where: string, map: unknown): ValueMap {
  if (!isObject(map)) {
    throw new TypeError(`${where} must be an object of label to app value`);
  }

  for (const [label, value] of Object.entries(map)) {
    if (!VALUE.test(label)) {
      throw new TypeError(`${where}: "${label}" is not a label`);
    }

    const list = value === null ? [] : Array.isArray(value) ? value : [value];

    if (
      (Array.isArray(value) && value.length === 0) ||
      !list.every((item) => typeof item === "string" && VALUE.test(item))
    ) {
      throw new TypeError(
        `${where}.${label} must be an app value, a non-empty list of app values, or null`,
      );
    }
  }

  // SAFETY: every entry was checked above.
  return map as ValueMap;
}

function isObject(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** The app values `label` reads from, `[]` when the app does not support it. */
export function appValues(
  map: ValueMap | undefined,
  label: string,
): readonly string[] {
  if (map === undefined || !Object.hasOwn(map, label)) {
    return [label];
  }

  const value = map[label];

  return value === null || value === undefined
    ? []
    : typeof value === "string"
      ? [value]
      : value;
}

/** Whether the map changes `label` (maps it to another value, several or none). */
function mapsLabel(map: ValueMap | undefined, label: string): boolean {
  const values = appValues(map, label);

  return values.length !== 1 || values[0] !== label;
}

/** SQL that raises `VALUE_UNSUPPORTED` for `label`, as a text expression. */
function unsupportedValue(label: string): string {
  return `better_supabase.value_unsupported(${sqlString(label)})`;
}

/**
 * The text expression `value` (a label) as the value the app stores: a `case`
 * over the mapped labels, unmapped labels unchanged. `value` itself without a
 * map.
 */
export function writeValue(map: ValueMap | undefined, value: string): string {
  const mapped = Object.keys(map ?? {}).filter((label) =>
    mapsLabel(map, label),
  );

  if (mapped.length === 0) {
    return value;
  }

  const whens = mapped.map((label) => {
    const [first] = appValues(map, label);

    return `when ${sqlString(label)} then ${first === undefined ? unsupportedValue(label) : sqlString(first)}`;
  });

  return `(case ${value} ${whens.join(" ")} else ${value} end)`;
}

/**
 * The column expression `value` as the block's label: every app value a label
 * maps to reads as that label, and any other value as itself. `value` itself
 * without a map.
 */
export function readValue(map: ValueMap | undefined, value: string): string {
  const pairs = Object.keys(map ?? {})
    .filter((label) => mapsLabel(map, label))
    .flatMap((label) =>
      appValues(map, label).map((app) => [app, label] as const),
    );

  if (pairs.length === 0) {
    return value;
  }

  const seen = new Set<string>();

  const whens = pairs.flatMap(([app, label]) => {
    if (seen.has(app)) {
      return [];
    }

    seen.add(app);

    return [`when ${sqlString(app)} then ${sqlString(label)}`];
  });

  return `(case (${value})::text ${whens.join(" ")} else (${value})::text end)`;
}

/**
 * Whether the column expression `value` holds one of `labels`: `value =
 * 'label'` or `value in (...)` over the mapped app values, `false` when the app
 * supports none of them. With `negate`, whether it holds none of them.
 */
export function valueIn(
  map: ValueMap | undefined,
  value: string,
  labels: readonly string[],
  negate = false,
): string {
  const values = [...new Set(labels.flatMap((label) => appValues(map, label)))];

  if (values.length === 0) {
    return negate ? "true" : "false";
  }

  if (values.length === 1 && labels.length === 1) {
    return `${value} ${negate ? "<>" : "="} ${sqlString(values[0]!)}`;
  }

  return `${value} ${negate ? "not in" : "in"} (${values.map((item) => sqlString(item)).join(", ")})`;
}

/** The `BlockSqlContext` methods that cast and map a typed column's values. */
export interface BlockSqlValueMethods {
  /**
   * `value`, a text expression, as the type of a logical column the table spec
   * lists in `typed`. On a table the app has, the column may be an enum or
   * another type with a text input, so the value goes through
   * `better_supabase.as_column_type`; on the module's own table it stays as it
   * is. With `invalid: "null"`, a value the type rejects, such as a label the
   * enum lacks, becomes null through `better_supabase.try_column_type` instead
   * of raising.
   */
  cast(
    table: string,
    column: string,
    value: string,
    invalid?: "raise" | "null",
  ): string;
  /**
   * The label `label` of a typed logical column as the SQL literal the app's
   * column stores, through `blocks.<name>.values`: the first mapped value, or a
   * call that raises `VALUE_UNSUPPORTED` for a label mapped to `null`. The
   * label itself without a map.
   */
  value(table: string, column: string, label: string): string;
  /**
   * Whether the column expression `value` holds one of `labels`, comparing
   * against every app value each label maps to: `value = 'label'` for one
   * label, `value in (...)` for several, `false` when none is supported.
   */
  is(
    table: string,
    column: string,
    value: string,
    labels: readonly string[],
    negate?: boolean,
  ): string;
  /**
   * The app values a label of a typed logical column reads from: `[label]`
   * without a map, `[]` for a label mapped to `null`.
   */
  appValues(table: string, column: string, label: string): readonly string[];
  /**
   * The column expression `value` of a typed logical column as the block's
   * label (mapped app values read back as their label), as text. `value` itself
   * without a map.
   */
  label(table: string, column: string, value: string): string;
  /**
   * ` || jsonb_build_object(...)` that replaces each mapped typed column of
   * `to_jsonb(alias)` with its label, keyed by the column's name; empty when no
   * column of `table` maps values.
   */
  labelsJson(table: string, alias: string): string;
  /**
   * `to_jsonb(alias)` of a row of `table` keyed as on the module's own table:
   * each logical column the app renames also under the module's column name,
   * and each mapped typed column read back as its label, so a client parses the
   * row the same way over the app's table. `as` gives the value of a renamed
   * logical column from its column expression, such as an int8 as text.
   * `to_jsonb(alias)` when nothing is renamed or mapped.
   */
  rowJson(
    table: string,
    alias: string,
    options?: {
      readonly as?: Readonly<Record<string, (value: string) => string>>;
    },
  ): string;
  /** Whether `blocks.<name>.values` maps any label of a typed logical column. */
  mapsValues(table: string, column: string): boolean;
}

/**
 * The value methods of a module context: `cast` wraps the table ownership's
 * cast with the map, and skips a `mappable` column that has no entry.
 */
export function valueMethods(input: {
  readonly tables: Readonly<
    Record<
      string,
      {
        readonly columns: Readonly<Record<string, string>>;
        readonly mappable?: readonly string[];
      }
    >
  >;
  readonly maps: ValueMaps;
  readonly cast: BlockSqlValueMethods["cast"];
  readonly column: (table: string, logical: string) => string;
  readonly mapped: (table: string, logical: string) => string | null;
  readonly own: (name: string) => string;
}): BlockSqlValueMethods {
  const { tables, maps, column } = input;
  const mapOf = (table: string, logical: string) => maps[table]?.[logical];

  const changes = (table: string, logical: string): boolean =>
    Object.keys(mapOf(table, logical) ?? {}).some((label) =>
      mapsLabel(mapOf(table, logical), label),
    );

  const cast: BlockSqlValueMethods["cast"] = (
    table,
    logical,
    value,
    invalid,
  ) =>
    tables[table]?.mappable?.includes(logical) === true &&
    mapOf(table, logical) === undefined
      ? value
      : input.cast(
          table,
          logical,
          writeValue(mapOf(table, logical), value),
          invalid,
        );

  return {
    cast,
    value(table, logical, label) {
      const map = mapOf(table, logical);

      if (!mapsLabel(map, label)) {
        return sqlString(label);
      }

      const [first] = appValues(map, label);

      return first === undefined
        ? input.cast(table, logical, unsupportedValue(label))
        : sqlString(first);
    },
    is: (table, logical, value, labels, negate) =>
      valueIn(mapOf(table, logical), value, labels, negate),
    appValues: (table, logical, label) =>
      appValues(mapOf(table, logical), label),
    label: (table, logical, value) => readValue(mapOf(table, logical), value),
    labelsJson(table, alias) {
      const mapped = Object.keys(maps[table] ?? {}).filter((logical) =>
        changes(table, logical),
      );

      if (mapped.length === 0) {
        return "";
      }

      return ` || jsonb_build_object(${mapped
        .map((logical) => {
          const name = column(table, logical);

          return `${sqlString(name)}, ${readValue(mapOf(table, logical), `${alias}.${sqlIdent(name)}`)}`;
        })
        .join(", ")})`;
    },
    rowJson(table, alias, options = {}) {
      const pairs = Object.entries(tables[table]?.columns ?? {}).flatMap(
        ([logical, name]) => {
          const app = input.mapped(table, logical);
          const own = input.own(name);
          const labelled = changes(table, logical);

          if (app === null || (app === own && !labelled)) {
            return [];
          }

          const value = `${alias}.${sqlIdent(app)}`;
          const as = options.as?.[logical];

          return [
            `${sqlString(own)}, ${
              labelled
                ? readValue(mapOf(table, logical), value)
                : as === undefined
                  ? value
                  : as(value)
            }`,
          ];
        },
      );

      return pairs.length === 0
        ? `to_jsonb(${alias})`
        : `(to_jsonb(${alias}) || jsonb_build_object(${pairs.join(", ")}))`;
    },
    mapsValues: changes,
  };
}

/** Whether raw `blocks.<name>.values` has an entry, even `{}`, for a column. */
export function hasValueEntry(
  values: unknown,
  table: string,
  column: string,
): boolean {
  const columns = isObject(values) ? values[table] : undefined;

  return isObject(columns) && columns[column] !== undefined;
}
