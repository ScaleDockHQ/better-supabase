import type {
  Condition,
  DeleteOp,
  InsertOp,
  Operation,
  OrderTerm,
  SelectOp,
  Selection,
  UpdateOp,
} from "../ir/types.ts";
import type { ColumnMeta, TableMeta } from "../schema/types.ts";

import { DbException, dbError } from "../core/errors.ts";
import { invalidRequest } from "../ir/build.ts";
import { simplifyOrFalse } from "../ir/simplify.ts";
import { lookupOf } from "../schema/lookup.ts";

/** A value SQLite binds: booleans become `0`/`1`, objects JSON text. */
export type SqliteValue = string | number | bigint | null;

export interface SqliteQuery {
  readonly text: string;
  readonly params: readonly SqliteValue[];
}

/** How the executor turns a returned SQLite value back into its PostgREST shape. */
export type SqliteDecode = "boolean" | "json" | "timestamptz" | "raw";

export interface SqliteColumn {
  /** Key in the returned row. */
  readonly alias: string;
  readonly decode: SqliteDecode;
}

/** Primary key values of the rows a write touches, in key column order. */
export type SqliteKeys = readonly (readonly SqliteValue[])[];

/** A read: the rows, a count, or both. */
export interface SqliteSelectPlan {
  readonly kind: "select";
  readonly rows: SqliteQuery | undefined;
  readonly count: SqliteQuery | undefined;
  readonly columns: readonly SqliteColumn[];
}

/**
 * An insert as one statement per row. PowerSync tables are views with
 * `INSTEAD OF` triggers, which take neither `RETURNING` nor `ON CONFLICT`,
 * so the executor checks for a conflicting row itself and reads the
 * written rows back by key.
 */
export interface SqliteInsertPlan {
  readonly kind: "insert";
  readonly rows: readonly {
    readonly key: readonly SqliteValue[];
    /** The row's tenant; an upsert never updates another tenant's row. */
    readonly tenant: SqliteValue | undefined;
    readonly insert: SqliteQuery;
    /** Finds a row that conflicts on the `onConflict` columns. */
    readonly existing: SqliteQuery | undefined;
    /** Updates the conflicting row (`onConflict.action: 'update'`), by its key. */
    readonly update: ((key: readonly SqliteValue[]) => SqliteQuery) | undefined;
  }[];
  readonly conflict: "update" | "ignore" | undefined;
  readonly returning: SqliteReturning | undefined;
}

/** An update or delete: select the keys, then write by key. */
export interface SqliteKeyedPlan {
  readonly kind: "update" | "delete";
  readonly keys: SqliteQuery;
  readonly apply: (keys: SqliteKeys) => SqliteQuery;
  readonly returning: SqliteReturning | undefined;
  /** More selected keys than this fails with `max_affected` before any write. */
  readonly maxAffected?: number;
}

export interface SqliteReturning {
  readonly read: (keys: SqliteKeys) => SqliteQuery;
  readonly columns: readonly SqliteColumn[];
}

export type SqlitePlan =
  | { readonly kind: "never" }
  | SqliteSelectPlan
  | SqliteInsertPlan
  | SqliteKeyedPlan;

export interface SqliteCompilerOptions {
  /**
   * The SQLite table or view for a table. Defaults to its database name
   * without the schema, which is how PowerSync names its views.
   */
  readonly tableName?: (table: TableMeta) => string;
}

/**
 * The operation needs something the SQLite dialect can't express: an
 * include (embedding), full-text search, a function source. Thrown while
 * compiling, before anything runs; executors return it as a `DbError` of
 * kind `unsupported`, with the feature in `details`.
 */
function unsupported(feature: string, table: TableMeta): never {
  throw new DbException(
    dbError(
      "unsupported",
      `SQLite can't run ${feature} on "${table.key}"; run this query on the server (PostgREST) instead`,
      { table: table.key, details: feature },
    ),
  );
}

export function quoteSqliteIdent(name: string): string {
  return `"${name.replaceAll('"', '""')}"`;
}

const TIMESTAMPS = new Set(["timestamptz", "timestamp"]);
const TEXT = new Set(["text", "varchar", "bpchar", "citext", "name"]);
// SQLite binds at most 32766 parameters; keyed statements stay well below.
const KEYS_PER_STATEMENT = 500;

function columnMeta(table: TableMeta, db: string): ColumnMeta | undefined {
  return lookupOf(table).byDb.get(db)?.[1];
}

function decodeOf(meta: ColumnMeta | undefined, cast?: "text"): SqliteDecode {
  if (!meta) return "raw";
  if (meta.type === "timestamptz") return "timestamptz";
  if (cast === "text") return "raw";
  if (meta.json || meta.array) return "json";
  if (meta.type === "bool") return "boolean";
  return "raw";
}

/** A JavaScript value as a SQLite parameter. */
export function sqliteValue(value: unknown): SqliteValue {
  if (value === null || value === undefined) return null;
  if (typeof value === "boolean") return value ? 1 : 0;
  if (typeof value === "number" || typeof value === "string") return value;
  if (typeof value === "bigint")
    return value >= BigInt(Number.MIN_SAFE_INTEGER) &&
      value <= BigInt(Number.MAX_SAFE_INTEGER)
      ? Number(value)
      : value;
  return JSON.stringify(value);
}

/**
 * A LIKE pattern (backslash escapes) as a GLOB pattern, which SQLite
 * matches case-sensitively, like Postgres `like`.
 */
export function likeToGlob(pattern: string): string {
  let out = "";
  for (let index = 0; index < pattern.length; index += 1) {
    const char = pattern[index]!;
    if (char === "\\" && index + 1 < pattern.length) {
      index += 1;
      out += globLiteral(pattern[index]!);
    } else if (char === "%") out += "*";
    else if (char === "_") out += "?";
    else out += globLiteral(char);
  }
  return out;
}

function globLiteral(char: string): string {
  return char === "*" || char === "?" || char === "[" ? `[${char}]` : char;
}

class SqliteCompiler {
  readonly params: SqliteValue[] = [];
  readonly #tableName: (table: TableMeta) => string;
  #aliases = 0;

  constructor(tableName: (table: TableMeta) => string) {
    this.#tableName = tableName;
  }

  alias(): string {
    const alias = `t${this.#aliases}`;
    this.#aliases += 1;
    return alias;
  }

  table(table: TableMeta): string {
    return quoteSqliteIdent(this.#tableName(table));
  }

  param(value: unknown): string {
    this.params.push(sqliteValue(value));
    return "?";
  }

  column(alias: string, name: string): string {
    return `${alias}.${quoteSqliteIdent(name)}`;
  }

  /** A column as compared and sorted: timestamps by their instant, not their text. */
  comparable(table: TableMeta, alias: string, name: string): string {
    const column = this.column(alias, name);
    return TIMESTAMPS.has(columnMeta(table, name)?.type ?? "")
      ? `julianday(${column})`
      : column;
  }

  comparableParam(table: TableMeta, name: string, value: unknown): string {
    const param = this.param(value);
    return TIMESTAMPS.has(columnMeta(table, name)?.type ?? "")
      ? `julianday(${param})`
      : param;
  }

  condition(condition: Condition, table: TableMeta, alias: string): string {
    switch (condition.kind) {
      case "and":
      case "or": {
        if (condition.items.length === 0)
          return condition.kind === "and" ? "1" : "0";
        const joiner = condition.kind === "and" ? " and " : " or ";
        return `(${condition.items.map((item) => this.condition(item, table, alias)).join(joiner)})`;
      }
      case "not":
        return `not ${this.condition(condition.item, table, alias)}`;
      case "column":
        return this.columnCondition(condition, table, alias);
      case "relation": {
        const target = this.alias();
        const join = this.join(condition, table, alias, target);
        const where =
          condition.quantifier === "every" && condition.where
            ? `not ${this.condition(condition.where, condition.target, target)}`
            : condition.where
              ? this.condition(condition.where, condition.target, target)
              : undefined;
        const body = `select 1 from ${this.table(condition.target)} as ${target} where ${join}${where ? ` and ${where}` : ""}`;
        return condition.quantifier === "some"
          ? `exists (${body})`
          : `not exists (${body})`;
      }
      default: {
        const exhaustive: never = condition;
        return exhaustive;
      }
    }
  }

  private join(
    condition: Extract<Condition, { kind: "relation" }>,
    source: TableMeta,
    sourceAlias: string,
    targetAlias: string,
  ): string {
    const { relation, target } = condition;
    if (relation.columns.length !== relation.references.length)
      invalidRequest(`Relation to "${target.key}" has mismatched columns`);
    return relation.columns
      .map((column, index) => {
        const reference = relation.references[index]!;
        return `${this.column(targetAlias, dbName(target, reference))} = ${this.column(sourceAlias, dbName(source, column))}`;
      })
      .join(" and ");
  }

  private columnCondition(
    condition: Extract<Condition, { kind: "column" }>,
    table: TableMeta,
    alias: string,
  ): string {
    const name = condition.column;
    if (condition.path) unsupported("a json path filter", table);
    const column = this.comparable(table, alias, name);
    const raw = this.column(alias, name);
    const { value } = condition;
    const operand = (): string => this.comparableParam(table, name, value);
    switch (condition.op) {
      case "eq":
        return `${column} = ${operand()}`;
      case "neq":
        return `${column} <> ${operand()}`;
      case "gt":
        return `${column} > ${operand()}`;
      case "gte":
        return `${column} >= ${operand()}`;
      case "lt":
        return `${column} < ${operand()}`;
      case "lte":
        return `${column} <= ${operand()}`;
      case "like":
        return `${raw} glob ${this.param(likeToGlob(String(value)))}`;
      case "ilike":
        return `${raw} like ${this.param(value)} escape '\\'`;
      case "in": {
        if (!Array.isArray(value)) invalidRequest('"in" needs an array');
        if (value.length === 0) return "0";
        const items: unknown[] = value;
        return `${column} in (${items.map((item) => this.comparableParam(table, name, item)).join(", ")})`;
      }
      case "is":
        if (value === null) return `${raw} is null`;
        if (value === true) return `${raw} is 1`;
        if (value === false) return `${raw} is 0`;
        return invalidRequest('"is" needs null, true or false');
      case "contains":
      case "containedBy":
      case "overlaps":
        return this.jsonCondition(condition.op, table, raw, value);
      case "fts":
        return unsupported("full-text search", table);
      case "match":
      case "imatch":
        return unsupported("a regular expression filter", table);
      default: {
        const exhaustive: never = condition.op;
        return exhaustive;
      }
    }
  }

  /** Arrays and jsonb sync to SQLite as JSON text; `json_each` reads them. */
  private jsonCondition(
    op: "contains" | "containedBy" | "overlaps",
    table: TableMeta,
    column: string,
    value: unknown,
  ): string {
    if (Array.isArray(value)) {
      const items: unknown[] = value;
      const distinct = [...new Set(items.map(sqliteValue))];
      if (distinct.some((item) => item === null))
        unsupported(`"${op}" with null elements`, table);
      const list = distinct.map((item) => this.param(item)).join(", ");
      switch (op) {
        case "contains":
          return distinct.length === 0
            ? `${column} is not null`
            : `(select count(distinct value) from json_each(${column}) where value in (${list})) = ${distinct.length}`;
        case "overlaps":
          return distinct.length === 0
            ? "0"
            : `exists (select 1 from json_each(${column}) where value in (${list}))`;
        case "containedBy":
          return `(${column} is not null and not exists (select 1 from json_each(${column})${distinct.length === 0 ? "" : ` where value not in (${list})`}))`;
        default: {
          const exhaustive: never = op;
          return exhaustive;
        }
      }
    }
    if (op !== "contains" || typeof value !== "object" || value === null)
      return unsupported(`"${op}" on a JSON object`, table);
    const parts: string[] = [];
    for (const [key, item] of Object.entries(value)) {
      if (key.includes('"') || (typeof item === "object" && item !== null))
        unsupported('"contains" with a nested JSON value', table);
      parts.push(
        item === null
          ? `json_type(${column}, ${this.param(`$."${key}"`)}) = 'null'`
          : `json_extract(${column}, ${this.param(`$."${key}"`)}) = ${this.param(item)}`,
      );
    }
    return parts.length === 0
      ? `${column} is not null`
      : `(${parts.join(" and ")})`;
  }

  /**
   * A column as sorted. Postgres sorts text by the database collation, which
   * ignores case at the first level, and enum types by their declared order.
   */
  sortable(table: TableMeta, alias: string, name: string): string {
    const meta = columnMeta(table, name);
    const column = this.column(alias, name);
    if (meta?.enum && !TEXT.has(meta.type)) {
      const cases = meta.enum
        .map((value, index) => `when ${this.param(value)} then ${index}`)
        .join(" ");
      return `case ${column} ${cases} end`;
    }
    if (meta && TEXT.has(meta.type) && !meta.array && !meta.json)
      return `${column} collate nocase`;
    return this.comparable(table, alias, name);
  }

  /** Postgres sorts nulls last ascending and first descending; SQLite does the opposite. */
  orderBy(
    terms: readonly OrderTerm[],
    table: TableMeta,
    alias: string,
  ): string {
    return terms
      .map((term) => {
        if (term.relation)
          unsupported(`a sort by the relation "${term.relation.name}"`, table);
        const nulls =
          term.nulls ?? (term.direction === "asc" ? "last" : "first");
        const key =
          term.aggregate === "count"
            ? "count(*)"
            : term.aggregate
              ? `${term.aggregate}(${this.sortable(table, alias, term.column)})`
              : this.sortable(table, alias, term.column);
        return `${key} ${term.direction} nulls ${nulls}`;
      })
      .join(", ");
  }

  selection(
    selection: Selection,
    table: TableMeta,
    alias: string,
  ): { readonly list: string; readonly columns: SqliteColumn[] } {
    if (selection.includes.length > 0) {
      const include = selection.includes[0]!;
      unsupported(
        include.count === undefined && include.aggregate === undefined
          ? `the include "${include.alias}" (embedding a related table)`
          : `the related ${include.count === undefined ? "aggregate" : "count"} "${include.alias}"`,
        table,
      );
    }
    const items: string[] = [];
    const columns: SqliteColumn[] = [];
    for (const entry of selection.columns) {
      const meta = columnMeta(table, entry.column);
      const column = this.column(alias, entry.column);
      const decode = decodeOf(meta, entry.cast);
      items.push(
        `${entry.cast === "text" && decode !== "timestamptz" ? `cast(${column} as text)` : column} as ${quoteSqliteIdent(entry.alias)}`,
      );
      columns.push({ alias: entry.alias, decode });
    }
    if (selection.aggregate) {
      if (selection.aggregate.count) {
        items.push(`count(*) as "_count"`);
        columns.push({ alias: "_count", decode: "raw" });
      }
      for (const measure of selection.aggregate.measures) {
        const meta = columnMeta(table, measure.column);
        const inner = `${measure.fn}(${this.comparable(table, alias, measure.column)})`;
        const timestamp =
          TIMESTAMPS.has(meta?.type ?? "") && measure.fn !== "avg";
        const expression = timestamp
          ? `${measure.fn}(${this.column(alias, measure.column)})`
          : measure.cast === "text"
            ? `cast(${inner} as text)`
            : inner;
        items.push(`${expression} as ${quoteSqliteIdent(measure.key)}`);
        columns.push({
          alias: measure.key,
          decode:
            timestamp && meta?.type === "timestamptz" ? "timestamptz" : "raw",
        });
      }
    }
    if (items.length === 0) items.push('1 as "_"');
    return { list: items.join(", "), columns };
  }
}

function dbName(table: TableMeta, app: string): string {
  const meta = table.columns[app];
  if (!meta)
    invalidRequest(`Unknown column "${app}" on "${table.key}"`, table.key);
  return meta.db;
}

function integer(value: number): number {
  if (!Number.isInteger(value) || value < 0)
    invalidRequest(`Expected a non-negative integer, got ${value}`);
  return value;
}

function whereClause(parts: readonly (string | undefined)[]): string {
  const present = parts.filter((part): part is string => part !== undefined);
  return present.length > 0 ? ` where ${present.join(" and ")}` : "";
}

function keyColumns(table: TableMeta): string[] {
  if (table.primaryKey.length === 0)
    unsupported("a write to a table without a primary key", table);
  return table.primaryKey.map((app) => dbName(table, app));
}

/** `where (a, b) in (values (?, ?), ...)` for a page of keys. */
function byKeys(
  compiler: SqliteCompiler,
  table: TableMeta,
  alias: string,
  keys: SqliteKeys,
): string {
  const columns = keyColumns(table);
  if (keys.length === 0) return "0";
  if (columns.length === 1)
    return `${compiler.column(alias, columns[0]!)} in (${keys.map((key) => compiler.param(key[0])).join(", ")})`;
  const tuple = `(${columns.map((column) => compiler.column(alias, column)).join(", ")})`;
  const values = keys
    .map((key) => `(${key.map((value) => compiler.param(value)).join(", ")})`)
    .join(", ");
  return `${tuple} in (values ${values})`;
}

/**
 * Compiles IR operations for SQLite (PowerSync's local database). Reads
 * become one statement; writes become steps the executor runs in a write
 * transaction. Throws a `DbException` with kind `unsupported` for what
 * SQLite can't express, before anything runs.
 */
export function compileSqlite(
  op: Operation,
  options: SqliteCompilerOptions = {},
): SqlitePlan {
  const tableName = options.tableName ?? ((table: TableMeta) => table.name);
  const make = (): SqliteCompiler => new SqliteCompiler(tableName);
  if (op.kind === "select" && op.source)
    unsupported(`the function source "${op.source.name}"`, op.table);
  switch (op.kind) {
    case "select":
      return selectPlan(make(), op);
    case "insert":
      return insertPlan(make, op);
    case "update":
    case "delete":
      return keyedPlan(make, op);
    default: {
      const exhaustive: never = op;
      return exhaustive;
    }
  }
}

function selectPlan(compiler: SqliteCompiler, op: SelectOp): SqlitePlan {
  const simple = simplifyOrFalse(op.where);
  if (simple.never) return { kind: "never" };
  const alias = compiler.alias();
  const { list, columns } = compiler.selection(op.selection, op.table, alias);
  const where = simple.condition
    ? compiler.condition(simple.condition, op.table, alias)
    : undefined;
  const filter = whereClause([where]);
  const from = `${compiler.table(op.table)} as ${alias}`;
  const filterParams = [...compiler.params];
  const count =
    op.count || op.head
      ? {
          text: `select count(*) as count from ${from}${filter}`,
          params: filterParams,
        }
      : undefined;
  if (op.head) return { kind: "select", rows: undefined, count, columns: [] };
  const group =
    op.selection.aggregate && op.selection.columns.length > 0
      ? ` group by ${op.selection.columns.map((entry) => compiler.column(alias, entry.column)).join(", ")}`
      : "";
  const order =
    op.orderBy.length > 0
      ? ` order by ${compiler.orderBy(op.orderBy, op.table, alias)}`
      : "";
  const limit =
    op.limit === undefined
      ? op.offset === undefined
        ? ""
        : " limit -1"
      : ` limit ${integer(op.limit)}`;
  const offset = op.offset === undefined ? "" : ` offset ${integer(op.offset)}`;
  return {
    kind: "select",
    rows: {
      text: `select ${list} from ${from}${filter}${group}${order}${limit}${offset}`,
      params: compiler.params,
    },
    count,
    columns,
  };
}

function returning(
  make: () => SqliteCompiler,
  op: { readonly table: TableMeta; readonly returning: Selection | undefined },
): SqliteReturning | undefined {
  if (!op.returning) return undefined;
  const probe = make();
  const columns = probe.selection(op.returning, op.table, "t0").columns;
  const selection = op.returning;
  return {
    columns,
    read: (keys) => {
      const compiler = make();
      const alias = compiler.alias();
      const { list } = compiler.selection(selection, op.table, alias);
      return {
        text: `select ${list} from ${compiler.table(op.table)} as ${alias} where ${byKeys(compiler, op.table, alias, keys)}`,
        params: compiler.params,
      };
    },
  };
}

function insertPlan(make: () => SqliteCompiler, op: InsertOp): SqlitePlan {
  if (op.rows.length === 0) return { kind: "never" };
  const keys = keyColumns(op.table);
  const columns = new Set<string>();
  for (const row of op.rows)
    for (const key of Object.keys(row)) columns.add(key);
  const ordered = [...columns];
  const conflict = op.onConflict;
  const tenant = op.table.flags.tenant;
  const tenantColumn =
    tenant === undefined ? undefined : op.table.columns[tenant]?.db;
  const rows = op.rows.map((row) => {
    const missing = keys.filter((key) => row[key] === undefined);
    if (missing.length > 0) {
      invalidRequest(
        `Insert into "${op.table.key}" needs ${missing.join(", ")}: SQLite has no column defaults for keys`,
        op.table.key,
      );
    }
    const own = ordered.filter((column) => column in row || op.defaultToNull);
    const insertCompiler = make();
    const values = own.map((column) =>
      insertCompiler.param(row[column] ?? null),
    );
    const insert = {
      text:
        own.length === 0
          ? `insert into ${insertCompiler.table(op.table)} default values`
          : `insert into ${insertCompiler.table(op.table)} (${own.map(quoteSqliteIdent).join(", ")}) values (${values.join(", ")})`,
      params: insertCompiler.params,
    };
    let existing: SqliteQuery | undefined;
    let update: ((key: readonly SqliteValue[]) => SqliteQuery) | undefined;
    if (conflict) {
      const find = make();
      const alias = find.alias();
      const match = conflict.columns
        .map(
          (column) =>
            `${find.column(alias, column)} = ${find.param(row[column] ?? null)}`,
        )
        .join(" and ");
      existing = {
        text: `select ${keys.map((key) => find.column(alias, key)).join(", ")}${tenantColumn ? `, ${find.column(alias, tenantColumn)} as "_tenant"` : ""} from ${find.table(op.table)} as ${alias} where ${match} limit 1`,
        params: find.params,
      };
      // PowerSync ids are immutable, and a filled-in id must not replace the existing one.
      const sets = own.filter(
        (column) =>
          !conflict.columns.includes(column) && !keys.includes(column),
      );
      if (conflict.action === "update" && sets.length > 0) {
        update = (key) => {
          const compiler = make();
          const alias = compiler.alias();
          const set = sets
            .map(
              (column) =>
                `${quoteSqliteIdent(column)} = ${compiler.param(row[column] ?? null)}`,
            )
            .join(", ");
          const where = byKeys(compiler, op.table, alias, [key]);
          return {
            text: `update ${compiler.table(op.table)} as ${alias} set ${set} where ${where}`,
            params: compiler.params,
          };
        };
      }
    }
    return {
      key: keys.map((key) => sqliteValue(row[key])),
      tenant:
        tenantColumn === undefined ? undefined : sqliteValue(row[tenantColumn]),
      insert,
      existing,
      update,
    };
  });
  return {
    kind: "insert",
    rows,
    conflict: conflict?.action,
    returning: returning(make, op),
  };
}

function keyedPlan(
  make: () => SqliteCompiler,
  op: UpdateOp | DeleteOp,
): SqlitePlan {
  const simple = simplifyOrFalse(op.where);
  if (simple.never) return { kind: "never" };
  const { maxAffected } = op;
  if (
    maxAffected !== undefined &&
    (!Number.isInteger(maxAffected) || maxAffected < 0)
  )
    invalidRequest(
      `"maxAffected" must be a non-negative integer, got ${maxAffected}`,
      op.table.key,
    );
  const keys = keyColumns(op.table);
  const compiler = make();
  const alias = compiler.alias();
  const where = simple.condition
    ? compiler.condition(simple.condition, op.table, alias)
    : undefined;
  const select: SqliteQuery = {
    text: `select ${keys.map((key) => compiler.column(alias, key)).join(", ")} from ${compiler.table(op.table)} as ${alias}${whereClause([where])}`,
    params: compiler.params,
  };
  let set: readonly [string, unknown][] = [];
  if (op.kind === "update") {
    set = Object.entries(op.set);
    if (set.length === 0)
      invalidRequest(`Update on "${op.table.key}" sets no columns`);
  }
  return {
    kind: op.kind,
    keys: select,
    apply: (rows) => {
      const own = make();
      const ownAlias = own.alias();
      const assignments = set
        .map(
          ([column, value]) =>
            `${quoteSqliteIdent(column)} = ${own.param(value)}`,
        )
        .join(", ");
      const target = byKeys(own, op.table, ownAlias, rows);
      return {
        text:
          op.kind === "update"
            ? `update ${own.table(op.table)} as ${ownAlias} set ${assignments} where ${target}`
            : `delete from ${own.table(op.table)} as ${ownAlias} where ${target}`,
        params: own.params,
      };
    },
    returning: returning(make, op),
    ...(maxAffected === undefined ? {} : { maxAffected }),
  };
}

/** Splits keys into pages that stay under SQLite's parameter limit. */
export function keyPages(keys: SqliteKeys): SqliteKeys[] {
  const pages: SqliteKeys[] = [];
  for (let start = 0; start < keys.length; start += KEYS_PER_STATEMENT)
    pages.push(keys.slice(start, start + KEYS_PER_STATEMENT));
  return pages;
}
