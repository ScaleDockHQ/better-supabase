import {
  APP_COLUMN_TYPES,
  type AppColumnConfig,
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

const TABLE_KEYS: ReadonlySet<string> = new Set([
  "columns",
  "scope",
  "timestamps",
]);

const COLUMN_KEYS: ReadonlySet<string> = new Set([
  "type",
  "nullable",
  "default",
  "unique",
  "references",
]);

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
function appReservedColumns(tenant = "organization"): readonly string[] {
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
  tables: ReadonlySet<string>,
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

  if (table !== AUTH_USERS && !tables.has(table)) {
    throw new TypeError(
      `${where}.table: "${table}" is neither an app table nor ${AUTH_USERS}; reference a block table with { block, table }`,
    );
  }

  if (type !== "uuid") {
    throw new TypeError(
      `${where}: a reference to ${table} needs a uuid column, not ${type}`,
    );
  }

  return { table, ...deletes };
}

function columnOf(
  where: string,
  value: unknown,
  tables: ReadonlySet<string>,
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

  return {
    type,
    ...(nullable === undefined ? {} : { nullable }),
    ...(fallback === undefined ? {} : { default: fallback }),
    ...(unique === undefined ? {} : { unique }),
    ...(references === undefined ? {} : { references }),
  };
}

function tableOf(
  where: string,
  value: unknown,
  tables: ReadonlySet<string>,
  reserved: ReadonlySet<string>,
): AppTableConfig {
  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, TABLE_KEYS);
  const { scope, columns } = value;

  if (scope !== undefined && !isScope(scope)) {
    throw new TypeError(`${where}.scope must be inherit, user or none`);
  }

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

  const tables = new Set(Object.keys(value));
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
