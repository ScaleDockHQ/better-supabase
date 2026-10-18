import {
  APP_COLUMN_FORMATS,
  APP_COLUMN_TYPES,
  type AppColumnConfig,
  type AppColumnFormat,
  type AppColumnType,
  type AppReference,
  type AppTableConfig,
  type AppTablesConfig,
} from "./types/app-tables.ts";

const IDENT = /^[a-z][a-z0-9_]{0,62}$/;
const BLOCK_NAME = /^[a-z][a-z0-9-]{0,62}$/;
const TEXT_LITERAL = /^'(?:[^'\\]|'')*'$/;
const INTEGER = /^-?\d{1,18}$/;
const NUMBER = /^-?\d{1,30}(?:\.\d{1,30})?$/;
const MAX_LITERAL = 200;

const MAX_OPTIONS = 100;
const MAX_OPTION = 100;
const MAX_COMMENT = 1000;
const MAX_KEY_SETS = 20;

/** Postgres keeps at most 32 columns in an index. */
const MAX_KEY_COLUMNS = 32;

const CONTROL = /\p{Cc}/u;

const TABLE_KEYS: ReadonlySet<string> = new Set([
  "columns",
  "scope",
  "timestamps",
  "id",
  "unique",
  "indexes",
  "comment",
]);

const COLUMN_KEYS: ReadonlySet<string> = new Set([
  "type",
  "nullable",
  "default",
  "unique",
  "references",
  "format",
  "options",
  "min",
  "max",
  "comment",
  "identity",
]);

/** The column types each format fits. */
const FORMAT_TYPES: Readonly<
  Record<AppColumnFormat, readonly AppColumnType[]>
> = {
  email: ["text"],
  url: ["text"],
  phone: ["text"],
  long_text: ["text"],
  color: ["text"],
  rating: ["integer", "bigint"],
  percent: ["integer", "numeric"],
  currency: ["bigint"],
};

const NUMBER_TYPES: ReadonlySet<AppColumnType> = new Set([
  "integer",
  "bigint",
  "numeric",
]);

const FORMATS: ReadonlySet<string> = new Set(APP_COLUMN_FORMATS);

const REFERENCE_KEYS: ReadonlySet<string> = new Set([
  "table",
  "block",
  "onDelete",
]);

const SCOPES: ReadonlySet<string> = new Set(["inherit", "user", "none"]);

const ON_DELETE: ReadonlySet<string> = new Set([
  "cascade",
  "restrict",
  "set null",
  "no action",
]);

const COLUMN_TYPES: ReadonlySet<string> = new Set(APP_COLUMN_TYPES);

/** The table every `auth.users` reference points at. */
export const AUTH_USERS = "auth.users";

type Json = Readonly<Record<string, unknown>>;

type AppTableId = NonNullable<AppTableConfig["id"]>;

function isObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isOnDelete(
  value: unknown,
): value is NonNullable<AppReference["onDelete"]> {
  return typeof value === "string" && ON_DELETE.has(value);
}

function isScope(
  value: unknown,
): value is NonNullable<AppTableConfig["scope"]> {
  return typeof value === "string" && SCOPES.has(value);
}

function isColumnType(value: unknown): value is AppColumnType {
  return typeof value === "string" && COLUMN_TYPES.has(value);
}

function isFormat(value: unknown): value is AppColumnFormat {
  return typeof value === "string" && FORMATS.has(value);
}

function commentOf(where: string, value: unknown): string | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (
    typeof value !== "string" ||
    value.length === 0 ||
    value.length > MAX_COMMENT ||
    value.includes("\0")
  ) {
    throw new TypeError(
      `${where} must be text of 1 to ${String(MAX_COMMENT)} characters`,
    );
  }

  return value;
}

function formatOf(
  where: string,
  value: unknown,
  type: AppColumnType,
): AppColumnFormat | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!isFormat(value)) {
    throw new TypeError(
      `${where} must be one of ${APP_COLUMN_FORMATS.join(", ")}`,
    );
  }

  const types = FORMAT_TYPES[value];

  if (!types.includes(type)) {
    throw new TypeError(
      `${where}: ${value} fits a ${types.join(" or ")} column, not ${type}`,
    );
  }

  return value;
}

function optionsOf(
  where: string,
  value: unknown,
  type: AppColumnType,
): readonly string[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (type !== "text" && type !== "text[]") {
    throw new TypeError(
      `${where}: options fit a text (single select) or text[] (multi-select) column, not ${type}`,
    );
  }

  if (
    !Array.isArray(value) ||
    value.length === 0 ||
    value.length > MAX_OPTIONS
  ) {
    throw new TypeError(
      `${where} must list 1 to ${String(MAX_OPTIONS)} values`,
    );
  }

  const seen = new Set<string>();

  for (const option of value) {
    if (
      typeof option !== "string" ||
      option.length === 0 ||
      option.length > MAX_OPTION ||
      CONTROL.test(option)
    ) {
      throw new TypeError(
        `${where}: each option is text of 1 to ${String(MAX_OPTION)} characters without control characters`,
      );
    }

    if (seen.has(option)) {
      throw new TypeError(`${where}: "${option}" is listed twice`);
    }

    seen.add(option);
  }

  return [...seen];
}

function boundOf(
  where: string,
  value: unknown,
  type: AppColumnType,
): number | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (typeof value !== "number" || !Number.isFinite(value)) {
    throw new TypeError(`${where} must be a number`);
  }

  if (type === "text") {
    if (!Number.isSafeInteger(value) || value < 0) {
      throw new TypeError(
        `${where}: a text length is a whole number of 0 or more`,
      );
    }

    return value;
  }

  if (!NUMBER_TYPES.has(type)) {
    throw new TypeError(
      `${where}: min and max fit a number or text column, not ${type}`,
    );
  }

  if (type !== "numeric" && !Number.isSafeInteger(value)) {
    throw new TypeError(`${where}: an ${type} bound is a whole number`);
  }

  return value;
}

function identityOf(
  where: string,
  value: unknown,
  column: Json,
  type: AppColumnType,
): boolean | undefined {
  const identity = optionalBoolean(where, value);

  if (identity !== true) {
    return identity;
  }

  if (type !== "integer" && type !== "bigint") {
    throw new TypeError(
      `${where}: an identity is an integer or bigint, not ${type}`,
    );
  }

  for (const key of ["default", "references", "options"] as const) {
    if (column[key] !== undefined) {
      throw new TypeError(`${where}: an identity takes no ${key}`);
    }
  }

  if (column["nullable"] === true) {
    throw new TypeError(`${where}: an identity is never null`);
  }

  return identity;
}

/**
 * The sets of columns of a composite `unique` or `indexes` key. Whether each
 * name is a column of the table is checked when the SQL renders, where the
 * scope column is known.
 */
function keySetsOf(
  where: string,
  value: unknown,
): readonly (readonly string[])[] | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!Array.isArray(value) || value.length > MAX_KEY_SETS) {
    throw new TypeError(
      `${where} must list at most ${String(MAX_KEY_SETS)} sets of columns`,
    );
  }

  return value.map((set: unknown, index) => {
    const at = `${where}[${String(index)}]`;

    if (
      !Array.isArray(set) ||
      set.length === 0 ||
      set.length > MAX_KEY_COLUMNS
    ) {
      throw new TypeError(
        `${at} must list 1 to ${String(MAX_KEY_COLUMNS)} column names`,
      );
    }

    const columns = set.map((column: unknown) => {
      if (typeof column !== "string" || !IDENT.test(column)) {
        throw new TypeError(
          `${at}: ${JSON.stringify(column)} is not a column name`,
        );
      }

      return column;
    });

    if (new Set(columns).size !== columns.length) {
      throw new TypeError(`${at} names a column twice`);
    }

    return columns;
  });
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

function optionalBoolean(where: string, value: unknown): boolean | undefined {
  if (value !== undefined && typeof value !== "boolean") {
    throw new TypeError(`${where} must be true or false`);
  }

  return value;
}

/**
 * The columns every app table gets, which `columns` may not name:
 * `id`, `created_at`, `updated_at`, `user_id` and the tenant column
 * (`organization_id`, or `<sql.naming.tenant>_id`), whatever the table's
 * scope, so changing the scope never collides with a column.
 */
export function appReservedColumns(tenant = "organization"): readonly string[] {
  return ["id", "created_at", "updated_at", "user_id", `${tenant}_id`];
}

/** Whether `value` is a default `type` accepts; see `AppColumnConfig.default`. */
export function isAppDefault(type: AppColumnType, value: string): boolean {
  switch (value) {
    case "now()": {
      return type === "timestamptz" || type === "date";
    }

    case "gen_random_uuid()":
    case "auth.uid()": {
      return type === "uuid";
    }

    case "true":
    case "false": {
      return type === "boolean";
    }

    case "'{}'": {
      return type === "jsonb" || type === "text[]" || type === "text";
    }

    case "'[]'": {
      return type === "jsonb" || type === "text";
    }

    default: {
      break;
    }
  }

  if (INTEGER.test(value)) {
    return type === "integer" || type === "bigint" || type === "numeric";
  }

  if (NUMBER.test(value)) {
    return type === "numeric";
  }

  return (
    value.length <= MAX_LITERAL &&
    TEXT_LITERAL.test(value) &&
    (type === "text" ||
      type === "uuid" ||
      type === "date" ||
      type === "timestamptz")
  );
}

function referenceOf(
  where: string,
  value: unknown,
  type: AppColumnType,
  nullable: boolean,
  tables: ReadonlyMap<string, AppTableId>,
): AppReference {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, REFERENCE_KEYS);
  const { table, block, onDelete } = value;

  if (typeof table !== "string") {
    throw new TypeError(`${where}.table must be a string`);
  }

  if (onDelete !== undefined && !isOnDelete(onDelete)) {
    throw new TypeError(
      `${where}.onDelete must be one of ${[...ON_DELETE].join(", ")}`,
    );
  }

  if (onDelete === "set null" && !nullable) {
    throw new TypeError(
      `${where}.onDelete: "set null" needs a nullable column`,
    );
  }

  const deletes = onDelete === undefined ? {} : { onDelete };

  if (block !== undefined) {
    if (typeof block !== "string" || !BLOCK_NAME.test(block)) {
      throw new TypeError(`${where}.block must be a block name`);
    }

    if (!IDENT.test(table)) {
      throw new TypeError(
        `${where}.table: "${table}" is not a logical table name of the ${block} block`,
      );
    }

    return { block, table, ...deletes };
  }

  const id = table === AUTH_USERS ? "uuid" : tables.get(table);

  if (id === undefined) {
    throw new TypeError(
      `${where}.table: "${table}" is neither an app table nor ${AUTH_USERS}; reference a block table with { block, table }`,
    );
  }

  if (type !== id) {
    throw new TypeError(
      `${where}: a reference to ${table} needs a ${id} column, not ${type}`,
    );
  }

  return { table, ...deletes };
}

function columnOf(
  where: string,
  value: unknown,
  tables: ReadonlyMap<string, AppTableId>,
): AppColumnConfig {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, COLUMN_KEYS);
  const { type } = value;

  if (!isColumnType(type)) {
    throw new TypeError(
      `${where}.type must be one of ${APP_COLUMN_TYPES.join(", ")}${type === "money" ? " (store money as bigint minor units next to a text currency column)" : ""}`,
    );
  }

  const nullable = optionalBoolean(`${where}.nullable`, value["nullable"]);
  const unique = optionalBoolean(`${where}.unique`, value["unique"]);
  const fallback = value["default"];

  if (
    fallback !== undefined &&
    (typeof fallback !== "string" || !isAppDefault(type, fallback))
  ) {
    throw new TypeError(
      `${where}.default: ${JSON.stringify(fallback)} is not an allowed ${type} default (now(), gen_random_uuid(), auth.uid(), true, false, a number, a 'quoted' literal, '{}' or '[]')`,
    );
  }

  const references =
    value["references"] === undefined
      ? undefined
      : referenceOf(
          `${where}.references`,
          value["references"],
          type,
          nullable !== false,
          tables,
        );

  const format = formatOf(`${where}.format`, value["format"], type);
  const options = optionsOf(`${where}.options`, value["options"], type);
  const min = boundOf(`${where}.min`, value["min"], type);
  const max = boundOf(`${where}.max`, value["max"], type);
  const comment = commentOf(`${where}.comment`, value["comment"]);

  const identity = identityOf(
    `${where}.identity`,
    value["identity"],
    value,
    type,
  );

  if (options !== undefined && format !== undefined) {
    throw new TypeError(
      `${where}: options make a select; drop the format ${format}`,
    );
  }

  if (min !== undefined && max !== undefined && min > max) {
    throw new TypeError(
      `${where}: min ${String(min)} is above max ${String(max)}`,
    );
  }

  return {
    type,
    ...(nullable === undefined ? {} : { nullable }),
    ...(fallback === undefined ? {} : { default: fallback }),
    ...(unique === undefined ? {} : { unique }),
    ...(references === undefined ? {} : { references }),
    ...(format === undefined ? {} : { format }),
    ...(options === undefined ? {} : { options }),
    ...(min === undefined ? {} : { min }),
    ...(max === undefined ? {} : { max }),
    ...(comment === undefined ? {} : { comment }),
    ...(identity === undefined ? {} : { identity }),
  };
}

function tableOf(
  where: string,
  value: unknown,
  tables: ReadonlyMap<string, AppTableId>,
  reserved: ReadonlySet<string>,
): AppTableConfig {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, TABLE_KEYS);
  const { scope, columns, id } = value;

  if (scope !== undefined && !isScope(scope)) {
    throw new TypeError(`${where}.scope must be inherit, user or none`);
  }

  if (id !== undefined && id !== "uuid" && id !== "bigint") {
    throw new TypeError(`${where}.id must be uuid or bigint`);
  }

  const unique = keySetsOf(`${where}.unique`, value["unique"]);
  const indexes = keySetsOf(`${where}.indexes`, value["indexes"]);
  const comment = commentOf(`${where}.comment`, value["comment"]);

  const timestamps = optionalBoolean(
    `${where}.timestamps`,
    value["timestamps"],
  );

  if (columns !== undefined && !isObject(columns)) {
    throw new TypeError(`${where}.columns must be an object keyed by column`);
  }

  const resolved = Object.entries(columns ?? {}).map(([name, column]) => {
    const at = `${where}.columns.${name}`;

    if (!IDENT.test(name)) {
      throw new TypeError(
        `${at}: "${name}" is not a lower snake identifier (a-z, 0-9 and _, starting with a letter)`,
      );
    }

    if (reserved.has(name)) {
      throw new TypeError(
        `${at}: "${name}" is a column every app table gets (${[...reserved].join(", ")})`,
      );
    }

    return [name, columnOf(at, column, tables)] as const;
  });

  return {
    ...(columns === undefined ? {} : { columns: Object.fromEntries(resolved) }),
    ...(scope === undefined ? {} : { scope }),
    ...(timestamps === undefined ? {} : { timestamps }),
    ...(id === undefined ? {} : { id }),
    ...(unique === undefined ? {} : { unique }),
    ...(indexes === undefined ? {} : { indexes }),
    ...(comment === undefined ? {} : { comment }),
  };
}

/**
 * `appTables` checked: lower snake table and column names, column types
 * from `APP_COLUMN_TYPES`, defaults from the allowlist, no reserved
 * columns, and references to another app table, `auth.users` or a block's
 * logical table. Whether a referenced block is installed, and whether a
 * name clashes with a block table, is checked when the SQL renders, where
 * the block registry is known. Throws a `TypeError` naming the key.
 */
export function appTablesOf(value: unknown, tenant?: string): AppTablesConfig {
  if (value === undefined) {
    return {};
  }

  if (!isObject(value)) {
    throw new TypeError("appTables must be an object keyed by table name");
  }

  const tables = new Map(
    Object.entries(value).map(([name, table]): [string, AppTableId] => [
      name,
      isObject(table) && table["id"] === "bigint" ? "bigint" : "uuid",
    ]),
  );

  const reserved = new Set(appReservedColumns(tenant));

  return Object.fromEntries(
    Object.entries(value).map(([name, table]) => {
      if (!IDENT.test(name) || name.startsWith("pg_")) {
        throw new TypeError(
          `appTables.${name}: "${name}" is not a lower snake identifier (a-z, 0-9 and _, starting with a letter)`,
        );
      }

      return [name, tableOf(`appTables.${name}`, table, tables, reserved)];
    }),
  );
}
