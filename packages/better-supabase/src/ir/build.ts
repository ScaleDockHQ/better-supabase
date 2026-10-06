import type { ColumnMeta, SchemaMeta, TableMeta } from "../schema/types.ts";

import { isPlainObject } from "../core/clone.ts";
import { DbException, dbError } from "../core/errors.ts";
import { relationMeta } from "../schema/define.ts";
import { lookupOf } from "../schema/lookup.ts";
import {
  type AggregateFn,
  type Condition,
  type Include,
  type Measure,
  type OrderTerm,
  type SelectColumn,
  type Selection,
  and,
  not,
  or,
} from "./types.ts";
import { encodeValue } from "./wire.ts";

const AGGREGATE_KEYS: Readonly<Record<string, AggregateFn>> = {
  _sum: "sum",
  _avg: "avg",
  _min: "min",
  _max: "max",
};

const NUMERIC_TYPES = new Set([
  "int2",
  "int4",
  "int8",
  "float4",
  "float8",
  "numeric",
  "smallint",
  "integer",
  "bigint",
  "real",
  "double precision",
]);

/** Thrown while building IR; surfaces as an `invalid_request` Result. */
export function invalidRequest(message: string, table?: string): never {
  throw new DbException(
    dbError("invalid_request", message, table ? { table } : {}),
  );
}

type Input = Readonly<Record<string, unknown>>;

const FIELD_OPS = new Set([
  "eq",
  "neq",
  "in",
  "notIn",
  "isNull",
  "not",
  "gt",
  "gte",
  "lt",
  "lte",
  "like",
  "ilike",
  "match",
  "imatch",
  "contains",
  "startsWith",
  "endsWith",
  "search",
  "hasEvery",
  "hasSome",
  "has",
  "containedBy",
]);

function isOpsObject(value: unknown): value is Input {
  if (!isPlainObject(value)) return false;
  const keys = Object.keys(value);
  return keys.length > 0 && keys.every((key) => FIELD_OPS.has(key));
}

function writable(meta: ColumnMeta, mode: "insert" | "update"): boolean {
  if (meta.generated || meta.identity === "always") return false;
  return mode === "insert"
    ? meta.insertable !== false
    : meta.updatable !== false;
}

/** A json key PostgREST accepts in an arrow path, or an array index. */
const JSON_KEY = /^[\w$]+$/;

/** Path filters compare text (`->>`), so numbers and booleans become strings. */
function text(value: unknown): unknown {
  return typeof value === "number" ||
    typeof value === "boolean" ||
    typeof value === "bigint"
    ? String(value)
    : value;
}

/** Escapes LIKE wildcards so user input matches literally. */
export function escapeLike(value: string): string {
  return value.replaceAll(/[\\%_]/g, (char) => `\\${char}`);
}

const builders = new WeakMap<SchemaMeta, IrBuilder>();

/** The shared builder for a schema; a builder holds no per-call state. */
export function builderFor(meta: SchemaMeta): IrBuilder {
  let builder = builders.get(meta);
  if (!builder) {
    builder = new IrBuilder(meta);
    builders.set(meta, builder);
  }
  return builder;
}

export class IrBuilder {
  readonly meta: SchemaMeta;
  /** Every column of a table, the selection of reads without `select`. */
  readonly #allColumns = new WeakMap<TableMeta, readonly SelectColumn[]>();

  constructor(meta: SchemaMeta) {
    this.meta = meta;
  }

  table(key: string): TableMeta {
    const table = this.meta.tables[key];
    if (!table) invalidRequest(`Unknown table "${key}"`);
    return table;
  }

  column(table: TableMeta, name: string): string {
    const column = table.columns[name];
    if (!column)
      invalidRequest(`Unknown column "${name}" on "${table.key}"`, table.key);
    return column.db;
  }

  // -------------------------------------------------------------------------
  // Where

  where(table: TableMeta, input: unknown): Condition | undefined {
    if (input === undefined) return undefined;
    if (!isPlainObject(input)) {
      invalidRequest(`"where" on "${table.key}" must be an object`, table.key);
    }
    const items: (Condition | undefined)[] = [];
    for (const [key, value] of Object.entries(input)) {
      if (value === undefined) continue;
      if (key === "AND") {
        const list = Array.isArray(value) ? value : [value];
        items.push(
          and(...list.map((item: unknown) => this.where(table, item))),
        );
      } else if (key === "OR") {
        if (!Array.isArray(value)) {
          invalidRequest(`"OR" on "${table.key}" must be an array`, table.key);
        }
        const branches = value
          .map((item: unknown) => this.where(table, item))
          .filter((item): item is Condition => item !== undefined);
        // An empty OR matches nothing, like SQL `false`.
        items.push(
          branches.length === 0
            ? not({ kind: "and", items: [] })
            : or(...branches),
        );
      } else if (key === "NOT") {
        const inner = this.where(table, value);
        if (inner) items.push(not(inner));
      } else if (key in table.relations) {
        items.push(this.relationFilter(table, key, value));
      } else {
        items.push(this.fieldFilter(table, key, value));
      }
    }
    return and(...items);
  }

  private relationFilter(
    table: TableMeta,
    name: string,
    value: unknown,
  ): Condition {
    const { relation, target } = relationMeta(this.meta, table, name);
    const make = (
      quantifier: "some" | "none" | "every",
      where: unknown,
    ): Condition => ({
      kind: "relation",
      name,
      relation,
      target,
      quantifier,
      where: where === null ? undefined : this.where(target, where),
    });

    if (relation.kind === "many") {
      if (!isPlainObject(value)) {
        invalidRequest(
          `Filter on to-many relation "${name}" needs some, none or every`,
          table.key,
        );
      }
      const items: Condition[] = [];
      for (const [quantifier, where] of Object.entries(value)) {
        if (where === undefined) continue;
        if (
          quantifier !== "some" &&
          quantifier !== "none" &&
          quantifier !== "every"
        ) {
          invalidRequest(
            `Unknown quantifier "${quantifier}" on relation "${name}"`,
            table.key,
          );
        }
        items.push(make(quantifier, where));
      }
      return and(...items) ?? make("some", {});
    }

    if (value === null) return make("none", null);
    if (isPlainObject(value)) {
      const keys = Object.keys(value);
      if (
        keys.length > 0 &&
        keys.every((key) => key === "is" || key === "isNot")
      ) {
        const items: Condition[] = [];
        if (value["is"] !== undefined) {
          items.push(
            value["is"] === null
              ? make("none", null)
              : make("some", value["is"]),
          );
        }
        if (value["isNot"] !== undefined) {
          items.push(
            value["isNot"] === null
              ? make("some", null)
              : not(make("some", value["isNot"])),
          );
        }
        return and(...items) ?? make("some", null);
      }
    }
    return make("some", value);
  }

  private fieldFilter(
    table: TableMeta,
    name: string,
    value: unknown,
  ): Condition {
    const column = this.column(table, name);
    if (value === null)
      return { kind: "column", column, op: "is", value: null };
    if (isPlainObject(value) && Array.isArray(value["path"])) {
      return this.pathFilter(table, name, column, value);
    }
    if (!isOpsObject(value)) {
      return { kind: "column", column, op: "eq", value: encodeValue(value) };
    }
    const items: Condition[] = [];
    for (const [op, operand] of Object.entries(value)) {
      if (operand === undefined) continue;
      items.push(this.fieldOp(table, name, column, op, operand));
    }
    return and(...items) ?? { kind: "and", items: [] };
  }

  /** `{ path: ["a", "b"], eq: "x" }` on a json column: compares the text at the path. */
  private pathFilter(
    table: TableMeta,
    name: string,
    column: string,
    input: Input,
  ): Condition {
    if (!table.columns[name]?.json) {
      invalidRequest(
        `"path" needs a json column; "${name}" on "${table.key}" is not one`,
        table.key,
      );
    }
    const path = input["path"];
    if (
      !Array.isArray(path) ||
      path.length === 0 ||
      !path.every((key) => typeof key === "string" && JSON_KEY.test(key))
    ) {
      invalidRequest(
        `"path" on "${name}" must be a non-empty list of keys made of letters, digits and _`,
        table.key,
      );
    }
    const keys: readonly string[] = path;
    const at = (
      op: Extract<Condition, { kind: "column" }>["op"],
      value: unknown,
    ): Condition => ({ kind: "column", column, op, value, path: keys });
    const items: Condition[] = [];
    for (const [op, operand] of Object.entries(input)) {
      if (op === "path" || operand === undefined) continue;
      switch (op) {
        case "eq":
          items.push(
            operand === null ? at("is", null) : at("eq", text(operand)),
          );
          break;
        case "neq":
          items.push(
            operand === null ? not(at("is", null)) : at("neq", text(operand)),
          );
          break;
        case "in":
        case "notIn": {
          if (!Array.isArray(operand)) {
            invalidRequest(`"${op}" on "${name}" needs an array`, table.key);
          }
          const condition = at("in", operand.map(text));
          items.push(op === "in" ? condition : not(condition));
          break;
        }
        case "isNull":
          items.push(operand ? at("is", null) : not(at("is", null)));
          break;
        case "gt":
        case "gte":
        case "lt":
        case "lte":
        case "like":
        case "ilike":
        case "match":
        case "imatch":
          items.push(at(op, text(operand)));
          break;
        default:
          invalidRequest(
            `Unknown operator "${op}" on a path of "${name}"`,
            table.key,
          );
      }
    }
    const condition = and(...items);
    if (!condition) {
      invalidRequest(`"path" on "${name}" needs an operator`, table.key);
    }
    return condition;
  }

  private fieldOp(
    table: TableMeta,
    name: string,
    column: string,
    op: string,
    operand: unknown,
  ): Condition {
    const col = (
      kind: Extract<Condition, { kind: "column" }>["op"],
      value: unknown,
    ): Condition => ({
      kind: "column",
      column,
      op: kind,
      value: encodeValue(value),
    });
    const meta = table.columns[name];
    const containment = (
      kind: "contains" | "containedBy" | "overlaps",
      value: unknown,
    ): Condition =>
      meta?.json
        ? {
            kind: "column",
            column,
            op: kind,
            value: encodeValue(value),
            json: true,
          }
        : col(kind, value);

    switch (op) {
      case "eq":
        return operand === null ? col("is", null) : col("eq", operand);
      case "neq":
        return operand === null ? not(col("is", null)) : col("neq", operand);
      case "in":
      case "notIn": {
        if (!Array.isArray(operand)) {
          invalidRequest(`"${op}" on "${name}" needs an array`, table.key);
        }
        const condition = col("in", operand);
        return op === "in" ? condition : not(condition);
      }
      case "isNull":
        return operand ? col("is", null) : not(col("is", null));
      case "not": {
        const inner = this.fieldFilter(table, name, operand);
        return not(inner);
      }
      case "gt":
      case "gte":
      case "lt":
      case "lte":
      case "like":
      case "ilike":
      case "match":
      case "imatch":
        return col(op, operand);
      case "contains":
        if (meta?.json || meta?.array) return containment("contains", operand);
        return col("ilike", `%${escapeLike(String(operand))}%`);
      case "startsWith":
        return col("like", `${escapeLike(String(operand))}%`);
      case "endsWith":
        return col("like", `%${escapeLike(String(operand))}`);
      case "search": {
        if (typeof operand === "string") return col("fts", operand);
        // SAFETY: a search operand is a query string or a query object, and the
        // string case returned above.
        const { query, config } = operand as { query: string; config?: string };
        return config
          ? { kind: "column", column, op: "fts", value: query, config }
          : col("fts", query);
      }
      case "hasEvery":
        return containment("contains", operand);
      case "has":
        return containment("contains", [operand]);
      case "hasSome":
        if (meta?.json) {
          invalidRequest(
            `"hasSome" on json column "${name}" has no PostgREST operator; use OR with "has"`,
            table.key,
          );
        }
        return col("overlaps", operand);
      case "containedBy":
        return containment("containedBy", operand);
      default:
        return invalidRequest(
          `Unknown operator "${op}" on "${name}"`,
          table.key,
        );
    }
  }

  // -------------------------------------------------------------------------
  // Selection

  selection(
    table: TableMeta,
    select: readonly string[] | undefined,
    include: unknown,
  ): Selection {
    const columns =
      select?.map((alias) => this.selectColumn(table, alias)) ??
      this.allColumns(table);
    const includes: Include[] = [];
    if (include !== undefined) {
      if (!isPlainObject(include)) {
        invalidRequest(
          `"include" on "${table.key}" must be an object`,
          table.key,
        );
      }
      for (const [name, value] of Object.entries(include)) {
        if (value === undefined || value === false) continue;
        const fn = AGGREGATE_KEYS[name];
        if (name === "_count") includes.push(...this.counts(table, value));
        else if (fn)
          includes.push(...this.relationAggregates(table, fn, value));
        else includes.push(this.include(table, name, value));
      }
    }
    return { columns, includes };
  }

  /**
   * `db.x.aggregate(args)`: the grouping columns, `_count` and the measures
   * of each group.
   */
  aggregation(table: TableMeta, args: Input): Selection {
    const groupBy = args["groupBy"] ?? [];
    if (!Array.isArray(groupBy)) {
      invalidRequest(`"groupBy" on "${table.key}" must be an array`, table.key);
    }
    const columns = groupBy.map((name: unknown) =>
      this.selectColumn(table, String(name)),
    );
    const measures: Measure[] = [];
    for (const [key, fn] of Object.entries(AGGREGATE_KEYS)) {
      const value = args[key];
      if (value === undefined) continue;
      for (const alias of this.measured(table, key, value)) {
        measures.push(this.measure(table, fn, alias, `${key}_${alias}`));
      }
    }
    const count = args["_count"] === true;
    if (!count && measures.length === 0) {
      invalidRequest(
        `aggregate on "${table.key}" needs _count, _sum, _avg, _min or _max`,
        table.key,
      );
    }
    return { columns, includes: [], aggregate: { count, measures } };
  }

  private relationAggregates(
    table: TableMeta,
    fn: AggregateFn,
    value: unknown,
  ): Include[] {
    const key = `_${fn}`;
    if (!isPlainObject(value)) {
      invalidRequest(
        `"${key}" on "${table.key}" must map relations to columns`,
        table.key,
      );
    }
    const includes: Include[] = [];
    for (const [name, entry] of Object.entries(value)) {
      if (entry === undefined || entry === false) continue;
      const { relation, target } = relationMeta(this.meta, table, name);
      if (relation.kind !== "many") {
        invalidRequest(
          `"${key}.${name}" on "${table.key}" needs a to-many relation`,
          table.key,
        );
      }
      const measures = this.measured(target, `${key}.${name}`, entry).map(
        (alias) => this.measure(target, fn, alias, alias),
      );
      if (measures.length === 0) continue;
      includes.push({
        alias: `${key}_${name}`,
        relation,
        target,
        selection: {
          columns: [],
          includes: [],
          aggregate: { count: false, measures },
        },
        where: undefined,
        orderBy: [],
        limit: undefined,
        required: false,
        aggregate: { fn, name },
      });
    }
    return includes;
  }

  /** The columns switched on in `{ amount: true, tax: true }`. */
  private measured(table: TableMeta, path: string, value: unknown): string[] {
    if (!isPlainObject(value)) {
      invalidRequest(
        `"${path}" on "${table.key}" must map columns to true`,
        table.key,
      );
    }
    return Object.entries(value)
      .filter(([, on]) => on === true)
      .map(([alias]) => alias);
  }

  private measure(
    table: TableMeta,
    fn: AggregateFn,
    alias: string,
    key: string,
  ): Measure {
    const column = this.column(table, alias);
    const meta = table.columns[alias];
    if (
      (fn === "sum" || fn === "avg") &&
      !NUMERIC_TYPES.has(meta?.type ?? "")
    ) {
      invalidRequest(
        `_${fn} needs a numeric column; "${alias}" on "${table.key}" is ${meta?.type}`,
        table.key,
      );
    }
    // avg is always a plain number; sum keeps exact int8/numeric codecs.
    const codec = fn === "avg" ? undefined : meta?.codec;
    if (!codec) return { fn, key, alias, column };
    return { fn, key, alias, column, cast: "text", codec };
  }

  private allColumns(table: TableMeta): readonly SelectColumn[] {
    let columns = this.#allColumns.get(table);
    if (!columns) {
      columns = Object.keys(table.columns).map((alias) =>
        this.selectColumn(table, alias),
      );
      this.#allColumns.set(table, columns);
    }
    return columns;
  }

  /** A selected column, with the cast and codec its metadata asks for. */
  selectColumn(table: TableMeta, alias: string): SelectColumn {
    const column = this.column(table, alias);
    const codec = table.columns[alias]?.codec;
    if (!codec) return { alias, column };
    return { alias, column, cast: "text", codec };
  }

  private counts(table: TableMeta, value: unknown): Include[] {
    if (!isPlainObject(value)) {
      invalidRequest(
        `"_count" on "${table.key}" must map relations to true or { where }`,
        table.key,
      );
    }
    const counts: Include[] = [];
    for (const [name, entry] of Object.entries(value)) {
      if (entry === undefined || entry === false) continue;
      const { relation, target } = relationMeta(this.meta, table, name);
      if (relation.kind !== "many") {
        invalidRequest(
          `"_count.${name}" on "${table.key}" needs a to-many relation`,
          table.key,
        );
      }
      const args: Input = isPlainObject(entry) ? entry : {};
      counts.push({
        alias: `_count_${name}`,
        relation,
        target,
        selection: { columns: [], includes: [] },
        where: this.where(target, args["where"]),
        orderBy: [],
        limit: undefined,
        required: false,
        count: name,
      });
    }
    return counts;
  }

  private include(table: TableMeta, name: string, value: unknown): Include {
    const { relation, target } = relationMeta(this.meta, table, name);
    const args: Input = value === true ? {} : isPlainObject(value) ? value : {};
    // SAFETY: the select option of every read method is a column list.
    return {
      alias: name,
      relation,
      target,
      selection: this.selection(
        target,
        args["select"] as readonly string[] | undefined,
        args["include"],
      ),
      where: this.where(target, args["where"]),
      orderBy: this.orderBy(target, args["orderBy"], "include"),
      limit: typeof args["limit"] === "number" ? args["limit"] : undefined,
      required: args["required"] === true,
    };
  }

  /**
   * Sort terms. On the root table, a to-one relation key sorts by the related
   * row's columns: `{ organization: { name: "asc" } }`.
   */
  orderBy(
    table: TableMeta,
    input: unknown,
    scope: "root" | "include" | "relation" = "root",
  ): OrderTerm[] {
    if (input === undefined) return [];
    const list: unknown[] = Array.isArray(input) ? input : [input];
    const terms: OrderTerm[] = [];
    for (const item of list) {
      if (!isPlainObject(item)) {
        invalidRequest(
          `"orderBy" on "${table.key}" must be an object`,
          table.key,
        );
      }
      for (const [name, spec] of Object.entries(item)) {
        if (spec === undefined) continue;
        if (!(name in table.columns) && name in table.relations) {
          terms.push(...this.relationOrder(table, name, spec, scope));
          continue;
        }
        const column = this.column(table, name);
        if (spec === "asc" || spec === "desc") {
          terms.push({ column, direction: spec });
        } else if (isPlainObject(spec)) {
          const direction = spec["direction"] === "desc" ? "desc" : "asc";
          const nulls = spec["nulls"];
          terms.push(
            nulls === "first" || nulls === "last"
              ? { column, direction, nulls }
              : { column, direction },
          );
        } else {
          invalidRequest(
            `Invalid sort for "${name}" on "${table.key}"`,
            table.key,
          );
        }
      }
    }
    return terms;
  }

  private relationOrder(
    table: TableMeta,
    name: string,
    spec: unknown,
    scope: "root" | "include" | "relation",
  ): OrderTerm[] {
    if (scope !== "root") {
      invalidRequest(
        scope === "include"
          ? `"orderBy" inside an include can't sort by the relation "${name}"`
          : `"orderBy" sorts by one level of relations; "${name}" on "${table.key}" is a second`,
        table.key,
      );
    }
    const { relation, target } = relationMeta(this.meta, table, name);
    if (relation.kind !== "one") {
      invalidRequest(
        `"orderBy" on "${name}" needs a to-one relation; "${name}" on "${table.key}" is to-many`,
        table.key,
      );
    }
    if (!isPlainObject(spec)) {
      invalidRequest(
        `"orderBy.${name}" on "${table.key}" must map columns of "${target.key}" to a direction`,
        table.key,
      );
    }
    return this.orderBy(target, spec, "relation").map((term) => ({
      ...term,
      relation: { name, relation, target },
    }));
  }

  /**
   * Maps an app-cased row to database column names. Rejects columns the
   * database won't accept for `mode`: generated columns, `identity always`
   * columns and read-only view columns.
   */
  row(
    table: TableMeta,
    input: unknown,
    mode: "insert" | "update" = "insert",
  ): Record<string, unknown> {
    if (!isPlainObject(input)) {
      invalidRequest(`Row for "${table.key}" must be an object`, table.key);
    }
    const out: Record<string, unknown> = {};
    for (const [name, value] of Object.entries(input)) {
      if (value === undefined) continue;
      const column = this.column(table, name);
      const meta = table.columns[name];
      if (meta && !writable(meta, mode)) {
        invalidRequest(
          `"${name}" on "${table.key}" is read-only${meta.generated ? " (generated)" : meta.identity === "always" ? " (identity always)" : ""} and can't be set in an ${mode}`,
          table.key,
        );
      }
      out[column] = encodeValue(value);
    }
    return out;
  }

  /**
   * Condition matching exactly one row by the primary key or by the columns
   * of a named unique key. The given columns must be one complete key.
   */
  uniqueKey(table: TableMeta, input: unknown): Condition {
    if (!isPlainObject(input)) {
      invalidRequest(`"where" on "${table.key}" must be an object`, table.key);
    }
    const given = Object.keys(input).filter((key) => input[key] !== undefined);
    const { keys } = lookupOf(table);
    const match = keys.find(
      (key) =>
        key.length > 0 &&
        key.length === given.length &&
        key.every((column) => given.includes(column)),
    );
    if (!match) {
      const names = keys
        .filter((key) => key.length > 0)
        .map((key) => `{ ${key.join(", ")} }`)
        .join(", ");
      invalidRequest(
        `findUnique on "${table.key}" needs one complete unique key: ${names}`,
        table.key,
      );
    }
    return {
      kind: "and",
      items: match.map((name) => ({
        kind: "column" as const,
        column: this.column(table, name),
        op: input[name] === null ? ("is" as const) : ("eq" as const),
        value: encodeValue(input[name]),
      })),
    };
  }

  /** Condition matching one primary key value. */
  primaryKey(table: TableMeta, id: unknown): Condition {
    const pk = table.primaryKey;
    if (pk.length === 0) {
      invalidRequest(`Table "${table.key}" has no primary key`, table.key);
    }
    if (pk.length === 1) {
      // SAFETY: the length check proves pk has exactly one column.
      const [name] = pk as [string];
      const value = isPlainObject(id) && name in id ? id[name] : id;
      return {
        kind: "column",
        column: this.column(table, name),
        op: "eq",
        value: encodeValue(value),
      };
    }
    if (!isPlainObject(id)) {
      invalidRequest(
        `Table "${table.key}" has a composite key; pass { ${pk.join(", ")} }`,
        table.key,
      );
    }
    return {
      kind: "and",
      items: pk.map((name) => ({
        kind: "column" as const,
        column: this.column(table, name),
        op: "eq" as const,
        value: encodeValue(id[name]),
      })),
    };
  }
}
