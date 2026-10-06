import type {
  Condition,
  Include,
  InsertOp,
  Operation,
  OrderTerm,
  Selection,
} from "../ir/types.ts";
import type { RelationMeta, TableMeta } from "../schema/types.ts";

import { invalidRequest } from "../ir/build.ts";
import { simplifyOrFalse } from "../ir/simplify.ts";
import { lookupOf } from "../schema/lookup.ts";

export interface SqlQuery {
  readonly text: string;
  readonly params: readonly unknown[];
}

/**
 * The SQL for one operation. `rows` returns a `row` json column per result
 * row; `count` returns one `count` column. Either may be absent: a HEAD read
 * only counts, a filter that can never match runs nothing.
 */
export interface SqlPlan {
  readonly rows: SqlQuery | undefined;
  readonly count: SqlQuery | undefined;
  /** No row can match; the executor returns an empty result without a query. */
  readonly never: boolean;
  /**
   * The rest of an insert split to stay under the bind-parameter limit. They
   * run after this plan, in the same transaction; rows and counts add up.
   */
  readonly chunks?: readonly SqlPlan[];
}

// The wire protocol counts bind parameters in 16 bits.
const MAX_PARAMS = 65_535;

// json_build_object takes at most 100 arguments.
const MAX_PAIRS = 50;

export function quoteIdent(name: string): string {
  return `"${name.replaceAll('"', '""')}"`;
}

function tableRef(table: TableMeta): string {
  return `${quoteIdent(table.schema)}.${quoteIdent(table.name)}`;
}

function dbColumn(table: TableMeta, app: string): string {
  const meta = table.columns[app];
  if (!meta)
    invalidRequest(`Unknown column "${app}" on "${table.key}"`, table.key);
  return meta.db;
}

function columnType(table: TableMeta, db: string): string | undefined {
  return lookupOf(table).byDb.get(db)?.[1].type;
}

type ColumnCondition = Extract<Condition, { kind: "column" }>;

/**
 * `a > x or (a = x and b > y) or ...` as `(a, b) > (x, y)`, which an index
 * on `(a, b)` serves. Both forms give the same result under SQL's
 * three-valued logic, nulls included.
 */
function rowComparison(condition: Extract<Condition, { kind: "or" }>): {
  readonly columns: string[];
  readonly op: "gt" | "lt";
  readonly values: unknown[];
} | null {
  const steps: ColumnCondition[] = [];
  for (const [index, item] of condition.items.entries()) {
    const terms = index === 0 ? [item] : item.kind === "and" ? item.items : [];
    if (terms.length !== index + 1) return null;
    const step = terms[index]!;
    if (
      step.kind !== "column" ||
      step.path ||
      (step.op !== "gt" && step.op !== "lt")
    )
      return null;
    for (const [at, term] of terms.slice(0, index).entries()) {
      const prev = steps[at]!;
      if (
        term.kind !== "column" ||
        term.op !== "eq" ||
        term.column !== prev.column ||
        !Object.is(term.value, prev.value)
      )
        return null;
    }
    steps.push(step);
  }
  const op = steps[0]?.op;
  if (op !== "gt" && op !== "lt") return null;
  if (steps.length < 2 || steps.some((step) => step.op !== op)) return null;
  return {
    columns: steps.map((step) => step.column),
    op,
    values: steps.map((step) => step.value),
  };
}

class SqlCompiler {
  readonly params: unknown[] = [];
  #aliases = 0;

  alias(): string {
    const alias = `t${this.#aliases}`;
    this.#aliases += 1;
    return alias;
  }

  param(value: unknown, cast?: string): string {
    this.params.push(value);
    return cast ? `$${this.params.length}::${cast}` : `$${this.params.length}`;
  }

  column(alias: string, name: string): string {
    return `${alias}.${quoteIdent(name)}`;
  }

  condition(condition: Condition, table: TableMeta, alias: string): string {
    switch (condition.kind) {
      case "and":
      case "or": {
        if (condition.items.length === 0)
          return condition.kind === "and" ? "true" : "false";
        const row = condition.kind === "or" ? rowComparison(condition) : null;
        if (row) {
          const columns = row.columns.map((name) => this.column(alias, name));
          const values = row.values.map((value) => this.param(value));
          return `(${columns.join(", ")}) ${row.op === "gt" ? ">" : "<"} (${values.join(", ")})`;
        }
        const joiner = condition.kind === "and" ? " and " : " or ";
        return `(${condition.items.map((item) => this.condition(item, table, alias)).join(joiner)})`;
      }
      case "not":
        return `not ${this.condition(condition.item, table, alias)}`;
      case "column":
        return this.columnCondition(condition, table, alias);
      case "relation": {
        const target = this.alias();
        const join = this.join(
          condition.relation,
          table,
          alias,
          condition.target,
          target,
        );
        const where =
          condition.quantifier === "every" && condition.where
            ? `not ${this.condition(condition.where, condition.target, target)}`
            : condition.where
              ? this.condition(condition.where, condition.target, target)
              : undefined;
        const body = `select 1 from ${tableRef(condition.target)} as ${target} where ${join}${where ? ` and ${where}` : ""}`;
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

  private columnCondition(
    condition: Extract<Condition, { kind: "column" }>,
    table: TableMeta,
    alias: string,
  ): string {
    const column = condition.path
      ? `(${this.column(alias, condition.column)} #>> ${this.param(condition.path, "text[]")})`
      : this.column(alias, condition.column);
    const { value } = condition;
    switch (condition.op) {
      case "eq":
        return `${column} = ${this.param(value)}`;
      case "neq":
        return `${column} <> ${this.param(value)}`;
      case "gt":
        return `${column} > ${this.param(value)}`;
      case "gte":
        return `${column} >= ${this.param(value)}`;
      case "lt":
        return `${column} < ${this.param(value)}`;
      case "lte":
        return `${column} <= ${this.param(value)}`;
      case "like":
        return `${column} like ${this.param(value)}`;
      case "ilike":
        return `${column} ilike ${this.param(value)}`;
      case "in":
        if (!Array.isArray(value)) invalidRequest('"in" needs an array');
        return `${column} = any(${this.param(value)})`;
      case "is":
        if (value === null) return `${column} is null`;
        if (value === true) return `${column} is true`;
        if (value === false) return `${column} is false`;
        return invalidRequest('"is" needs null, true or false');
      case "contains":
      case "containedBy":
      case "overlaps": {
        const operator =
          condition.op === "contains"
            ? "@>"
            : condition.op === "containedBy"
              ? "<@"
              : "&&";
        return Array.isArray(value) && !condition.json
          ? `${column} ${operator} ${this.param(value)}`
          : `${column} ${operator} ${this.param(JSON.stringify(value), "jsonb")}`;
      }
      case "fts": {
        const config = condition.config
          ? `${this.param(condition.config, "regconfig")}, `
          : "";
        const query = `websearch_to_tsquery(${config}${this.param(value)})`;
        const vector =
          columnType(table, condition.column) === "tsvector"
            ? column
            : `to_tsvector(${config}${column})`;
        return `${vector} @@ ${query}`;
      }
      default: {
        const exhaustive: never = condition.op;
        return exhaustive;
      }
    }
  }

  join(
    relation: RelationMeta,
    source: TableMeta,
    sourceAlias: string,
    target: TableMeta,
    targetAlias: string,
  ): string {
    if (relation.columns.length !== relation.references.length)
      invalidRequest(`Relation to "${target.key}" has mismatched columns`);
    return relation.columns
      .map((column, index) => {
        const reference = relation.references[index];
        if (reference === undefined)
          invalidRequest(`Relation to "${target.key}" has mismatched columns`);
        return `${this.column(targetAlias, dbColumn(target, reference))} = ${this.column(sourceAlias, dbColumn(source, column))}`;
      })
      .join(" and ");
  }

  orderBy(terms: readonly OrderTerm[], alias: string): string {
    return terms
      .map((term) => {
        const nulls = term.nulls ? ` nulls ${term.nulls}` : "";
        return `${this.column(alias, term.column)} ${term.direction}${nulls}`;
      })
      .join(", ");
  }

  /** `json_build_object('alias', t0."col", ...)` for a selection. */
  rowExpression(selection: Selection, table: TableMeta, alias: string): string {
    const pairs: string[] = selection.columns.map(
      (entry) =>
        `'${entry.alias.replaceAll("'", "''")}', ${this.column(alias, entry.column)}${entry.cast ? `::${entry.cast}` : ""}`,
    );
    if (selection.aggregate) {
      if (selection.aggregate.count) pairs.push(`'_count', count(*)`);
      for (const measure of selection.aggregate.measures) {
        pairs.push(
          `'${measure.key.replaceAll("'", "''")}', ${measure.fn}(${this.column(alias, measure.column)})${measure.cast ? `::${measure.cast}` : ""}`,
        );
      }
    }
    for (const include of selection.includes) {
      pairs.push(
        `'${include.alias.replaceAll("'", "''")}', ${this.include(include, table, alias)}`,
      );
    }
    if (pairs.length <= MAX_PAIRS)
      return `json_build_object(${pairs.join(", ")})`;
    const chunks: string[] = [];
    for (let index = 0; index < pairs.length; index += MAX_PAIRS) {
      chunks.push(
        `jsonb_build_object(${pairs.slice(index, index + MAX_PAIRS).join(", ")})`,
      );
    }
    return `(${chunks.join(" || ")})::json`;
  }

  /** Conditions an include adds to its parent: `required` includes need a match. */
  requiredIncludes(
    selection: Selection,
    table: TableMeta,
    alias: string,
  ): string[] {
    return selection.includes
      .filter((include) => include.required)
      .map((include) => {
        const target = this.alias();
        const where = this.includeWhere(include, table, alias, target);
        return `exists (select 1 from ${tableRef(include.target)} as ${target} where ${where})`;
      });
  }

  private includeWhere(
    include: Include,
    parent: TableMeta,
    parentAlias: string,
    alias: string,
  ): string {
    const parts = [
      this.join(include.relation, parent, parentAlias, include.target, alias),
    ];
    const simple = simplifyOrFalse(include.where);
    if (simple.never) parts.push("false");
    else if (simple.condition)
      parts.push(this.condition(simple.condition, include.target, alias));
    parts.push(
      ...this.requiredIncludes(include.selection, include.target, alias),
    );
    return parts.join(" and ");
  }

  private include(
    include: Include,
    parent: TableMeta,
    parentAlias: string,
  ): string {
    const alias = this.alias();
    const where = this.includeWhere(include, parent, parentAlias, alias);
    const from = `from ${tableRef(include.target)} as ${alias} where ${where}`;
    if (include.count !== undefined) return `(select count(*) ${from})`;
    const row = this.rowExpression(include.selection, include.target, alias);
    if (include.selection.aggregate) return `(select ${row} ${from})`;
    if (include.relation.kind === "one") {
      return `(select ${row} ${from} limit 1)`;
    }
    const order =
      include.orderBy.length > 0
        ? this.orderBy(include.orderBy, alias)
        : undefined;
    const limit =
      include.limit === undefined ? "" : ` limit ${integer(include.limit)}`;
    const rank = `row_number() over (${order ? `order by ${order}` : ""})`;
    const inner = `select ${row} as r, ${rank} as o ${from}${order ? ` order by ${order}` : ""}${limit}`;
    return `(select coalesce(json_agg(s.r order by s.o), '[]'::json) from (${inner}) as s)`;
  }
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

function insertColumns(op: InsertOp): string[] {
  const columns = new Set<string>();
  for (const row of op.rows)
    for (const key of Object.keys(row)) columns.add(key);
  return [...columns];
}

function returningRows(
  compiler: SqlCompiler,
  op: { readonly returning: Selection | undefined; readonly table: TableMeta },
  alias: string,
): string {
  return op.returning
    ? ` returning ${compiler.rowExpression(op.returning, op.table, alias)} as row`
    : " returning 1";
}

/** Compiles an operation to parameterized SQL. Rows come back as json. */
export function compileSql(op: Operation): SqlPlan {
  const compiler = new SqlCompiler();
  const alias = compiler.alias();
  const source = op.kind === "select" ? op.source : undefined;
  const from = source
    ? `${quoteIdent(source.schema)}.${quoteIdent(source.name)}(${Object.entries(
        source.args,
      )
        .map(
          ([name, value]) => `${quoteIdent(name)} => ${compiler.param(value)}`,
        )
        .join(", ")}) as ${alias}`
    : `${tableRef(op.table)} as ${alias}`;

  switch (op.kind) {
    case "select": {
      const simple = simplifyOrFalse(op.where);
      if (simple.never)
        return { rows: undefined, count: undefined, never: true };
      const where = simple.condition
        ? compiler.condition(simple.condition, op.table, alias)
        : undefined;
      const required = compiler.requiredIncludes(op.selection, op.table, alias);
      const filter = whereClause([where, ...required]);
      const countText = op.count
        ? `select count(*)::int as count from ${from}${filter}`
        : undefined;
      if (op.head) {
        const countQuery = {
          text:
            countText ?? `select count(*)::int as count from ${from}${filter}`,
          params: [...compiler.params],
        };
        return { rows: undefined, count: countQuery, never: false };
      }
      const countQuery = countText
        ? { text: countText, params: [...compiler.params] }
        : undefined;
      const row = compiler.rowExpression(op.selection, op.table, alias);
      const group =
        op.selection.aggregate && op.selection.columns.length > 0
          ? ` group by ${op.selection.columns.map((entry) => compiler.column(alias, entry.column)).join(", ")}`
          : "";
      const order =
        op.orderBy.length > 0
          ? ` order by ${compiler.orderBy(op.orderBy, alias)}`
          : "";
      const limit = op.limit === undefined ? "" : ` limit ${integer(op.limit)}`;
      const offset =
        op.offset === undefined ? "" : ` offset ${integer(op.offset)}`;
      return {
        rows: {
          text: `select ${row} as row from ${from}${filter}${group}${order}${limit}${offset}`,
          params: compiler.params,
        },
        count: countQuery,
        never: false,
      };
    }
    case "insert": {
      if (op.rows.length === 0)
        return { rows: undefined, count: undefined, never: true };
      const columns = insertColumns(op);
      const perChunk = Math.floor(MAX_PARAMS / Math.max(columns.length, 1));
      if (op.rows.length <= perChunk)
        return insertPlan(compiler, from, alias, op, columns);
      const [first, ...rest] = chunk(op.rows, perChunk).map((rows) => {
        const own = new SqlCompiler();
        const ownAlias = own.alias();
        return insertPlan(
          own,
          `${tableRef(op.table)} as ${ownAlias}`,
          ownAlias,
          { ...op, rows },
          columns,
        );
      });
      return { ...first!, chunks: rest };
    }
    case "update": {
      const simple = simplifyOrFalse(op.where);
      if (simple.never)
        return { rows: undefined, count: undefined, never: true };
      const entries = Object.entries(op.set);
      if (entries.length === 0)
        invalidRequest(`Update on "${op.table.key}" sets no columns`);
      const set = entries
        .map(
          ([column, value]) =>
            `${quoteIdent(column)} = ${compiler.param(value)}`,
        )
        .join(", ");
      const where = simple.condition
        ? compiler.condition(simple.condition, op.table, alias)
        : undefined;
      const statement = `update ${from} set ${set}${whereClause([where])}${returningRows(compiler, op, alias)}`;
      return mutation(statement, op.returning !== undefined, compiler.params);
    }
    case "delete": {
      const simple = simplifyOrFalse(op.where);
      if (simple.never)
        return { rows: undefined, count: undefined, never: true };
      const where = simple.condition
        ? compiler.condition(simple.condition, op.table, alias)
        : undefined;
      const statement = `delete from ${from}${whereClause([where])}${returningRows(compiler, op, alias)}`;
      return mutation(statement, op.returning !== undefined, compiler.params);
    }
    default: {
      const exhaustive: never = op;
      return exhaustive;
    }
  }
}

function chunk<T>(items: readonly T[], size: number): T[][] {
  const out: T[][] = [];
  for (let start = 0; start < items.length; start += size)
    out.push(items.slice(start, start + size));
  return out;
}

function insertPlan(
  compiler: SqlCompiler,
  from: string,
  alias: string,
  op: InsertOp,
  columns: readonly string[],
): SqlPlan {
  let body: string;
  if (columns.length === 0) {
    if (op.rows.length > 1)
      invalidRequest("Cannot insert several rows without columns");
    body = "default values";
  } else {
    const values = op.rows.map(
      (row) =>
        `(${columns
          .map((column) =>
            column in row
              ? compiler.param(row[column])
              : op.defaultToNull
                ? "null"
                : "default",
          )
          .join(", ")})`,
    );
    body = `(${columns.map(quoteIdent).join(", ")}) values ${values.join(", ")}`;
  }
  let conflict = "";
  if (op.onConflict) {
    const target = `(${op.onConflict.columns.map(quoteIdent).join(", ")})`;
    const updates = columns.map(
      (column) => `${quoteIdent(column)} = excluded.${quoteIdent(column)}`,
    );
    conflict =
      op.onConflict.action === "ignore" || updates.length === 0
        ? ` on conflict ${target} do nothing`
        : ` on conflict ${target} do update set ${updates.join(", ")}${tenantGuard(op, alias)}`;
  }
  const statement = `insert into ${from} ${body}${conflict}${returningRows(compiler, op, alias)}`;
  return mutation(statement, op.returning !== undefined, compiler.params);
}

/** An upsert never updates a row that belongs to another tenant. */
function tenantGuard(op: InsertOp, alias: string): string {
  const app = op.table.flags.tenant;
  const column = app === undefined ? undefined : op.table.columns[app]?.db;
  if (column === undefined) return "";
  return ` where ${alias}.${quoteIdent(column)} = excluded.${quoteIdent(column)}`;
}

function mutation(
  statement: string,
  returning: boolean,
  params: readonly unknown[],
): SqlPlan {
  if (returning)
    return {
      rows: { text: statement, params },
      count: undefined,
      never: false,
    };
  return {
    rows: undefined,
    count: {
      text: `with m as (${statement}) select count(*)::int as count from m`,
      params,
    },
    never: false,
  };
}
