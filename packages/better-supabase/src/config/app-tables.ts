import type { BlockScope } from "./blocks.ts";
import type {
  AppColumnConfig,
  AppColumnFormat,
  AppColumnType,
  AppReference,
  AppTableConfig,
  AppTableEventKind,
  AppTableEvents,
  AppTableVersions,
  AppTableSubject,
  AppTablesConfig,
} from "./types/app-tables.ts";
import type { SubjectConfig, SubjectsConfig } from "./types/subjects.ts";

import { FIELD_FORMATS } from "../core/contracts/field-formats.ts";
import { accessOf, checkColumnAccess } from "./app-access.ts";
import { computedOf, hasComputed } from "./app-computed.ts";
import {
  APP_COLUMN_FORMATS,
  APP_COLUMN_TYPES,
  APP_ON_DELETE_ACTIONS,
  APP_TABLE_EVENT_KINDS,
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
  "subject",
  "rollups",
  "lookups",
  "events",
]);

const SUBJECT_KEYS: ReadonlySet<string> = new Set([
  "type",
  "title",
  "url",
  "search",
  "permissions",
  "rank",
  "softDelete",
  "versions",
]);

/** The columns `subject.rank` and `subject.softDelete` add. */
export const APP_RANK_COLUMN = "rank";
export const APP_DELETED_AT_COLUMN = "deleted_at";

const PLACEHOLDER = /\{([^}]*)\}/gu;

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
  "access",
]);

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

const ON_DELETE: ReadonlySet<string> = new Set(APP_ON_DELETE_ACTIONS);

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

  const types: readonly AppColumnType[] = FIELD_FORMATS[value].types;

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
 * The columns every app table gets, which `columns` may not name: `id`,
 * `created_at`, `updated_at`, `user_id` and the tenant column
 * (`organization_id`, or `<sql.naming.tenant>_id`), whatever the table's scope,
 * so changing the scope never collides with a column.
 */
export function appReservedColumns(tenant = "organization"): readonly string[] {
  return ["id", "created_at", "updated_at", "user_id", `${tenant}_id`];
}

/**
 * Postgres truncates identifiers past 63 bytes, so longer generated names
 * collide.
 */
const MAX_IDENTIFIER = 63;

/** The longest app table or column name: `<table>_view` still fits in 63 bytes. */
export const APP_NAME_MAX: number = MAX_IDENTIFIER - "_view".length;

/**
 * Why `name` can't name an app table or column, or `undefined` when it can:
 * lower snake case starting with a letter, not `pg_`, and at most
 * `APP_NAME_MAX` characters.
 */
export function appIdentifierError(name: string): string | undefined {
  if (name === "") {
    return "Enter a name.";
  }

  if (name.length > APP_NAME_MAX) {
    return `Use at most ${String(APP_NAME_MAX)} characters.`;
  }

  if (!IDENT.test(name)) {
    return "Use lower-case letters, digits and underscores, starting with a letter.";
  }

  if (name.startsWith("pg_")) {
    return "Names starting with pg_ are reserved by Postgres.";
  }

  return undefined;
}

/**
 * The first constraint or index name the SQL derives for `table` that is longer
 * than 63 bytes, which Postgres would truncate into a collision, as a message;
 * `undefined` when every name fits.
 */
export function appNameLengthError(
  table: string,
  config: Pick<AppTableConfig, "columns" | "unique" | "indexes">,
): string | undefined {
  const names = [
    ...Object.entries(config.columns ?? {}).flatMap(([column, each]) =>
      each.references !== undefined ||
      each.format !== undefined ||
      each.options !== undefined ||
      each.min !== undefined ||
      each.max !== undefined
        ? [`${table}_${column}_check`]
        : [],
    ),
    ...(config.unique ?? []).map((set) => `${table}_${set.join("_")}_key`),
    ...(config.indexes ?? []).map((set) => `${table}_${set.join("_")}_idx`),
  ];

  const long = names.find((name) => name.length > MAX_IDENTIFIER);

  return long === undefined
    ? undefined
    : `${long} is longer than ${String(MAX_IDENTIFIER)} characters; use shorter table or column names`;
}

/** The defaults `isAppDefault` accepts, per type, as a message names them. */
const DEFAULT_EXAMPLES: Record<AppColumnType, string> = {
  text: "a 'quoted' text",
  integer: "a whole number",
  bigint: "a whole number",
  numeric: "a number",
  boolean: "true or false",
  uuid: "gen_random_uuid(), auth.uid() or a 'quoted' value",
  timestamptz: "now() or a 'quoted' value",
  date: "now() or a 'quoted' value",
  jsonb: "'{}' or '[]'",
  "text[]": "'{}'",
};

/**
 * Why `value` can't be the default of `column`, or `undefined` when it can: it
 * must be on the `isAppDefault` allowlist, one of the column's `options`, and
 * inside its bounds (`min`, `max`, or those of its format).
 */
export function appDefaultError(
  column: Pick<AppColumnConfig, "type" | "options" | "min" | "max" | "format">,
  value: string,
): string | undefined {
  const { type } = column;

  if (!isAppDefault(type, value)) {
    return `A ${type} column takes ${DEFAULT_EXAMPLES[type]} as its default.`;
  }

  const literal = TEXT_LITERAL.test(value)
    ? value.slice(1, -1).replaceAll("''", "'")
    : undefined;

  if (
    type === "text" &&
    column.options !== undefined &&
    literal !== undefined &&
    !column.options.includes(literal)
  ) {
    return `The default must be one of the options: ${column.options.join(", ")}.`;
  }

  const bounds =
    column.format === undefined
      ? undefined
      : FIELD_FORMATS[column.format].bounds;

  const min = column.min ?? bounds?.[0];
  const max = column.max ?? bounds?.[1];

  const size =
    type === "text"
      ? literal?.length
      : NUMBER.test(value)
        ? Number(value)
        : undefined;

  if (size === undefined) {
    return undefined;
  }

  const what = type === "text" ? "length" : "value";

  if (min !== undefined && size < min) {
    return `The default's ${what} is below the minimum of ${String(min)}.`;
  }

  if (max !== undefined && size > max) {
    return `The default's ${what} is above the maximum of ${String(max)}.`;
  }

  return undefined;
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

  const access = accessOf(`${where}.access`, value["access"]);

  if (
    access !== undefined &&
    nullable === false &&
    fallback === undefined &&
    identity !== true
  ) {
    throw new TypeError(
      `${where}: signed-in users can't write a column with access ${access}, so a required one needs a default`,
    );
  }

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

  const outside =
    typeof fallback === "string"
      ? appDefaultError(
          {
            type,
            ...(options === undefined ? {} : { options }),
            ...(min === undefined ? {} : { min }),
            ...(max === undefined ? {} : { max }),
            ...(format === undefined ? {} : { format }),
          },
          fallback,
        )
      : undefined;

  if (outside !== undefined) {
    throw new TypeError(`${where}.default: ${outside}`);
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
    ...(access === undefined ? {} : { access }),
  };
}

function namedColumn(
  where: string,
  value: unknown,
  columns: ReadonlySet<string>,
): string {
  if (typeof value !== "string" || !columns.has(value)) {
    throw new TypeError(
      `${where} must name a column of the table (${[...columns].join(", ")})`,
    );
  }

  return value;
}

function searchOf(
  where: string,
  value: unknown,
  columns: ReadonlySet<string>,
): AppTableSubject["search"] {
  if (value === undefined) {
    return undefined;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, new Set(["title", "body"]));
  const { title, body } = value;

  if (body !== undefined && !Array.isArray(body)) {
    throw new TypeError(`${where}.body must be a list of columns`);
  }

  return {
    ...(title === undefined
      ? {}
      : { title: namedColumn(`${where}.title`, title, columns) }),
    ...(body === undefined
      ? {}
      : {
          body: body.map((each: unknown) =>
            namedColumn(`${where}.body`, each, columns),
          ),
        }),
  };
}

function permissionsOf(
  where: string,
  value: unknown,
): Readonly<Record<string, string>> | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (
    !isObject(value) ||
    Object.values(value).some((key) => typeof key !== "string" || key === "")
  ) {
    throw new TypeError(`${where} must map each action to a permission key`);
  }

  return Object.fromEntries(
    Object.entries(value).map(([action, key]) => [action, String(key)]),
  );
}

function rankOf(
  where: string,
  value: unknown,
  columns: ReadonlySet<string>,
): AppTableSubject["rank"] {
  if (value === undefined || value === true) {
    return value;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be true or { group }`);
  }

  checkKeys(where, value, new Set(["group"]));

  return value["group"] === undefined
    ? {}
    : { group: namedColumn(`${where}.group`, value["group"], columns) };
}

/**
 * `subject.versions` checked: `true`, or `columns` from the table's own columns
 * (not its id, scope or timestamps, which a restore must not write) and
 * `auto`.
 */
function versionsOf(
  where: string,
  value: unknown,
  editable: ReadonlySet<string>,
): true | AppTableVersions | undefined {
  if (value === undefined || value === true) {
    return value;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be true or { columns, auto }`);
  }

  checkKeys(where, value, new Set(["columns", "auto"]));
  const { columns } = value;

  if (
    columns !== undefined &&
    (!Array.isArray(columns) || columns.length === 0)
  ) {
    throw new TypeError(`${where}.columns must list one or more columns`);
  }

  const listed = columns?.map((name: unknown, index: number) =>
    namedColumn(`${where}.columns[${index}]`, name, editable),
  );

  const auto = optionalBoolean(`${where}.auto`, value["auto"]);

  return {
    ...(listed === undefined ? {} : { columns: [...new Set(listed)] }),
    ...(auto === undefined ? {} : { auto }),
  };
}

/**
 * The columns and snapshot mode `subject.versions` registers with the versions
 * block.
 */
export function appTableVersions(
  table: AppTableConfig,
): { readonly columns: readonly string[]; readonly auto: boolean } | undefined {
  const versions = table.subject?.versions;

  if (versions === undefined) {
    return undefined;
  }

  const options = versions === true ? {} : versions;

  return {
    columns: options.columns ?? Object.keys(table.columns ?? {}),
    auto: options.auto ?? true,
  };
}

/**
 * `subject` checked against the table's columns. `columns` holds every column
 * the table has, the ones `rank` and `softDelete` add included; `editable`
 * holds the table's own columns.
 */
function subjectOf(
  where: string,
  value: unknown,
  columns: ReadonlySet<string>,
  editable: ReadonlySet<string>,
): AppTableSubject | undefined {
  if (value === undefined) {
    return undefined;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be an object`);
  }

  checkKeys(where, value, SUBJECT_KEYS);
  const { type, title, url } = value;

  if (typeof type !== "string" || !IDENT.test(type)) {
    throw new TypeError(
      `${where}.type must be lowercase letters, digits and underscores, starting with a letter`,
    );
  }

  if (url !== undefined) {
    if (typeof url !== "string" || !url.startsWith("/")) {
      throw new TypeError(`${where}.url must be a path starting with /`);
    }

    for (const [, name] of url.matchAll(PLACEHOLDER)) {
      namedColumn(`${where}.url {${name ?? ""}}`, name, columns);
    }
  }

  const search = searchOf(`${where}.search`, value["search"], columns);

  const permissions = permissionsOf(
    `${where}.permissions`,
    value["permissions"],
  );

  const rank = rankOf(`${where}.rank`, value["rank"], columns);

  const softDelete = optionalBoolean(
    `${where}.softDelete`,
    value["softDelete"],
  );

  const versions = versionsOf(`${where}.versions`, value["versions"], editable);

  return {
    type,
    ...(title === undefined
      ? {}
      : { title: namedColumn(`${where}.title`, title, columns) }),
    ...(url === undefined ? {} : { url }),
    ...(search === undefined ? {} : { search }),
    ...(permissions === undefined ? {} : { permissions }),
    ...(rank === undefined ? {} : { rank }),
    ...(softDelete === undefined ? {} : { softDelete }),
    ...(versions === undefined ? {} : { versions }),
  };
}

/** The columns the subject adds, which `columns` may not name. */
function subjectColumnsOf(value: unknown): readonly string[] {
  if (!isObject(value)) {
    return [];
  }

  return [
    ...(value["rank"] === undefined ? [] : [APP_RANK_COLUMN]),
    ...(value["softDelete"] === true ? [APP_DELETED_AT_COLUMN] : []),
  ];
}

/** The event kinds `events` turns on; empty without it. */
export function appTableEventKinds(
  table: AppTableConfig,
): readonly AppTableEventKind[] {
  const events = table.events;

  if (events === undefined) {
    return [];
  }

  return events === true
    ? APP_TABLE_EVENT_KINDS
    : (events.on ?? APP_TABLE_EVENT_KINDS);
}

/** The event types an app table emits: `<subject type or table>.<kind>`. */
export function appTableEventTypes(
  name: string,
  table: AppTableConfig,
): readonly string[] {
  const base = table.subject?.type ?? name;

  return appTableEventKinds(table).map((kind) => `${base}.${kind}`);
}

function isEventKind(value: unknown): value is AppTableEventKind {
  return APP_TABLE_EVENT_KINDS.some((kind) => kind === value);
}

/**
 * `events` checked: `true`, or `on` from the event kinds and `include` from the
 * table's columns.
 */
function eventsOf(
  where: string,
  value: unknown,
  columns: ReadonlySet<string>,
): true | AppTableEvents | undefined {
  if (value === undefined || value === true) {
    return value;
  }

  if (!isObject(value)) {
    throw new TypeError(`${where} must be true or { on, include }`);
  }

  checkKeys(where, value, new Set(["on", "include"]));
  const { on, include } = value;

  if (
    on !== undefined &&
    (!Array.isArray(on) || on.length === 0 || !on.every(isEventKind))
  ) {
    throw new TypeError(
      `${where}.on must list one or more of ${APP_TABLE_EVENT_KINDS.join(", ")}`,
    );
  }

  if (include !== undefined && !Array.isArray(include)) {
    throw new TypeError(`${where}.include must be a list of columns`);
  }

  const included = include?.map((name: unknown, index: number) =>
    namedColumn(`${where}.include[${index}]`, name, columns),
  );

  return {
    ...(on === undefined ? {} : { on: [...new Set(on)] }),
    ...(included === undefined ? {} : { include: [...new Set(included)] }),
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

  const added = subjectColumnsOf(value["subject"]);

  const resolved = Object.entries(columns ?? {}).map(([name, column]) => {
    const at = `${where}.columns.${name}`;

    const invalid = appIdentifierError(name);

    if (invalid !== undefined) {
      throw new TypeError(`${at}: "${name}" is not a column name. ${invalid}`);
    }

    if (reserved.has(name)) {
      throw new TypeError(
        `${at}: "${name}" is a column every app table gets (${[...reserved].join(", ")})`,
      );
    }

    if (added.includes(name)) {
      throw new TypeError(
        `${at}: "${name}" is the column ${where}.subject adds; remove it from columns`,
      );
    }

    return [name, columnOf(at, column, tables)] as const;
  });

  const subject = subjectOf(
    `${where}.subject`,
    value["subject"],
    new Set([...reserved, ...added, ...resolved.map(([name]) => name)]),
    new Set(resolved.map(([name]) => name)),
  );

  const events = eventsOf(
    `${where}.events`,
    value["events"],
    new Set([...reserved, ...added, ...resolved.map(([name]) => name)]),
  );

  return {
    ...(columns === undefined ? {} : { columns: Object.fromEntries(resolved) }),
    ...(scope === undefined ? {} : { scope }),
    ...(timestamps === undefined ? {} : { timestamps }),
    ...(id === undefined ? {} : { id }),
    ...(unique === undefined ? {} : { unique }),
    ...(indexes === undefined ? {} : { indexes }),
    ...(comment === undefined ? {} : { comment }),
    ...(subject === undefined ? {} : { subject }),
    ...(events === undefined ? {} : { events }),
  };
}

/**
 * `appTables` checked: lower snake table and column names, column types from
 * `APP_COLUMN_TYPES`, defaults from the allowlist, no reserved columns, and
 * references to another app table, `auth.users` or a block's logical table.
 * Whether a referenced block is installed, and whether a name clashes with a
 * block table, is checked when the SQL renders, where the block registry is
 * known. Throws a `TypeError` naming the key.
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

  const resolved: AppTablesConfig = Object.fromEntries(
    Object.entries(value).map(([name, table]) => {
      const invalid = appIdentifierError(name);

      if (invalid !== undefined) {
        throw new TypeError(
          `appTables.${name}: "${name}" is not a table name. ${invalid}`,
        );
      }

      const checked = tableOf(`appTables.${name}`, table, tables, reserved);
      const long = appNameLengthError(name, checked);

      if (long !== undefined) {
        throw new TypeError(`appTables.${name}: ${long}`);
      }

      return [name, checked];
    }),
  );

  const checked: AppTablesConfig = Object.fromEntries(
    Object.entries(resolved).map(([name, table]) => {
      const where = `appTables.${name}`;

      const computed = computedOf(
        where,
        value[name],
        name,
        resolved,
        new Set([
          ...reserved,
          ...Object.keys(table.columns ?? {}),
          ...subjectColumnsOf(table.subject),
        ]),
      );

      const withComputed = { ...table, ...computed };

      if (
        hasComputed(withComputed) &&
        Object.hasOwn(resolved, `${name}_view`)
      ) {
        throw new TypeError(
          `${where}: its rollups and lookups go in the view ${name}_view, which is also an app table; rename one`,
        );
      }

      return [name, withComputed];
    }),
  );

  checkColumnAccess(checked);

  return checked;
}

/**
 * `subjects` with the subject of every app table that sets one (ADR 0043): the
 * table in `public`, its id type, and its tenant column, or `false` for a table
 * kept per user or shared. `scope` is `sql.scope` and `tenant` is
 * `sql.naming.tenant`. Throws when a type is taken twice.
 */
export function withAppTableSubjects(
  subjects: SubjectsConfig,
  appTables: AppTablesConfig,
  scope: BlockScope | undefined,
  tenant = "organization",
): SubjectsConfig {
  const merged: Record<string, SubjectConfig> = { ...subjects };

  for (const [name, table] of Object.entries(appTables)) {
    const subject = table.subject;

    if (subject === undefined) {
      continue;
    }

    const where = `appTables.${name}.subject`;

    if (Object.hasOwn(merged, subject.type)) {
      throw new TypeError(
        `${where}.type: "${subject.type}" is already a subject type; choose another type or remove subjects.${subject.type}`,
      );
    }

    const kept =
      table.scope === undefined || table.scope === "inherit"
        ? (scope ?? "tenant")
        : table.scope;

    merged[subject.type] = {
      table: `public.${name}`,
      idType: table.id ?? "uuid",
      tenant: kept === "tenant" ? `${tenant}_id` : false,
      ...(subject.title === undefined ? {} : { title: subject.title }),
      ...(subject.url === undefined ? {} : { url: subject.url }),
      ...(subject.search === undefined ? {} : { search: subject.search }),
      ...(subject.permissions === undefined
        ? {}
        : { permissions: subject.permissions }),
      ...(subject.softDelete === true
        ? { deletedAt: APP_DELETED_AT_COLUMN }
        : {}),
      ...versionsEntry(table),
      ...(subject.rank === undefined
        ? {}
        : {
            rank: {
              column: APP_RANK_COLUMN,
              ...(subject.rank === true || subject.rank.group === undefined
                ? {}
                : { group: subject.rank.group }),
            },
          }),
    };
  }

  return merged;
}

function versionsEntry(table: AppTableConfig): Pick<SubjectConfig, "versions"> {
  const versions = appTableVersions(table);

  return versions === undefined ? {} : { versions };
}
