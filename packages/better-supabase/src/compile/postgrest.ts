import type {
  Aggregation,
  Condition,
  Include,
  Measure,
  Operation,
  OrderTerm,
  SelectColumn,
  Selection,
} from "../ir/types.ts";
import type { RelationMeta, TableMeta } from "../schema/types.ts";

import { temporalText } from "../core/temporal.ts";
import { invalidRequest } from "../ir/build.ts";
import { simplifyOrFalse } from "../ir/simplify.ts";

/**
 * A compiled PostgREST request, expressed as calls on the public
 * postgrest-js builder so it works with any supabase-js client.
 */
export interface PostgrestPlan {
  /** `select` parameter, or `undefined` for mutations without returning. */
  readonly select: string | undefined;
  readonly filters: readonly PlanFilter[];
  readonly orders: readonly PlanOrder[];
  readonly limits: readonly PlanLimit[];
  readonly range: { readonly from: number; readonly to: number } | undefined;
  /** The condition can never match; skip the request. */
  readonly never: boolean;
}

export type PlanFilter =
  | {
      readonly kind: "filter";
      readonly path: string;
      readonly operator: string;
      readonly value: string;
    }
  | {
      readonly kind: "or";
      readonly expression: string;
      readonly referencedTable: string | undefined;
    };

export interface PlanOrder {
  readonly column: string;
  readonly ascending: boolean;
  readonly nullsFirst: boolean | undefined;
  readonly referencedTable: string | undefined;
}

export interface PlanLimit {
  readonly count: number;
  readonly referencedTable: string | undefined;
}

interface EmbedNode {
  readonly alias: string;
  readonly target: TableMeta;
  readonly relation: RelationMeta;
  readonly inner: boolean;
  readonly columns: readonly SelectColumn[];
  readonly children: EmbedNode[];
  /** Render `count` instead of columns (`_count` includes). */
  readonly count?: boolean;
  /** Render these aggregates instead of columns (`_sum` and friends). */
  readonly measures?: readonly Measure[];
}

// ---------------------------------------------------------------------------
// Value formatting

function scalar(value: unknown): string {
  if (typeof value === "string") return value;
  if (typeof value === "number" || typeof value === "boolean")
    return String(value);
  const temporalValue = temporalText(value);
  if (temporalValue !== undefined) return temporalValue;
  if (
    typeof value === "number" ||
    typeof value === "bigint" ||
    typeof value === "boolean"
  ) {
    return String(value);
  }
  if (value === null) return "null";
  return JSON.stringify(value);
}

/** Double-quotes a value for PostgREST lists and logic trees. */
function quote(value: unknown): string {
  const text = scalar(value);
  return `"${text.replaceAll("\\", "\\\\").replaceAll('"', '\\"')}"`;
}

/**
 * Values PostgREST reads the same with or without quotes in an `in` list:
 * uuids, numbers, ISO dates and times, enum values, slugs and emails.
 * `null` stays quoted, so it keeps meaning the string.
 */
const BARE = /^[\w.:+@-]+$/;

/** An `in` list element; quoted only when it needs to be, as supabase-js does. */
function listItem(value: unknown): string {
  const text = scalar(value);
  return BARE.test(text) && text.toLowerCase() !== "null" ? text : quote(text);
}

function list(values: readonly unknown[], open: string, close: string): string {
  return `${open}${values.map(quote).join(",")}${close}`;
}

/** The filter target: the column, or `column->a->>b` for a json path. */
function target(condition: Extract<Condition, { kind: "column" }>): string {
  const { column, path } = condition;
  if (!path || path.length === 0) return column;
  const last = path.length - 1;
  return `${column}${path.map((key, index) => `${index === last ? "->>" : "->"}${key}`).join("")}`;
}

function isBoolLike(value: unknown): value is null | boolean {
  return value === null || typeof value === "boolean";
}

function operatorAndValue(
  condition: Extract<Condition, { kind: "column" }>,
  inLogic: boolean,
): { operator: string; value: string } {
  const { op, value } = condition;
  const plain = (text: unknown): string =>
    inLogic ? quote(text) : scalar(text);
  switch (op) {
    case "eq":
    case "neq":
    case "gt":
    case "gte":
    case "lt":
    case "lte":
    case "like":
    case "ilike":
    case "match":
    case "imatch":
      return { operator: op, value: plain(value) };
    case "in":
      if (!Array.isArray(value)) invalidRequest('"in" needs an array');
      return {
        operator: "in",
        value: `(${value.map(listItem).join(",")})`,
      };
    case "is":
      if (!isBoolLike(value)) invalidRequest('"is" needs null, true or false');
      return { operator: "is", value: String(value) };
    case "contains":
    case "containedBy":
    case "overlaps": {
      const operator =
        op === "contains" ? "cs" : op === "containedBy" ? "cd" : "ov";
      if (Array.isArray(value) && !condition.json) {
        return { operator, value: list(value, "{", "}") };
      }
      const json = JSON.stringify(value);
      return { operator, value: inLogic ? quote(json) : json };
    }
    case "fts": {
      const operator = condition.config ? `wfts(${condition.config})` : "wfts";
      return { operator, value: plain(value) };
    }
    default: {
      const exhaustive: never = op;
      return exhaustive;
    }
  }
}

// ---------------------------------------------------------------------------
// Compiler

class PostgrestCompiler {
  readonly filters: PlanFilter[] = [];
  readonly orders: PlanOrder[] = [];
  readonly limits: PlanLimit[] = [];
  #counter = 0;

  nextAlias(): string {
    this.#counter += 1;
    return `_bs${this.#counter}`;
  }

  /** Compiles a condition at `path` where top-level items are ANDed. */
  andContext(
    condition: Condition,
    path: string | undefined,
    embeds: EmbedNode[],
  ): void {
    switch (condition.kind) {
      case "and":
        for (const item of condition.items) this.andContext(item, path, embeds);
        return;
      case "column": {
        const { operator, value } = operatorAndValue(condition, false);
        this.filters.push({
          kind: "filter",
          path: path ? `${path}.${target(condition)}` : target(condition),
          operator,
          value,
        });
        return;
      }
      case "not": {
        const inner = condition.item;
        if (inner.kind === "column") {
          const { operator, value } = operatorAndValue(inner, false);
          this.filters.push({
            kind: "filter",
            path: path ? `${path}.${target(inner)}` : target(inner),
            operator: `not.${operator}`,
            value,
          });
          return;
        }
        if (inner.kind === "relation") {
          this.relationAnd(negateRelation(inner), path, embeds);
          return;
        }
        if (inner.kind === "not") {
          this.andContext(inner.item, path, embeds);
          return;
        }
        this.filters.push({
          kind: "or",
          expression: this.logic(condition, embeds),
          referencedTable: path,
        });
        return;
      }
      case "or":
        this.filters.push({
          kind: "or",
          expression: this.logic(condition, embeds)
            .replace(/^or\(/, "")
            .replace(/\)$/, ""),
          referencedTable: path,
        });
        return;
      case "relation":
        this.relationAnd(condition, path, embeds);
        return;
      default: {
        const exhaustive: never = condition;
        return exhaustive;
      }
    }
  }

  private relationAnd(
    condition: Extract<Condition, { kind: "relation" }>,
    path: string | undefined,
    embeds: EmbedNode[],
  ): void {
    if (condition.quantifier === "every" && !condition.where) return;
    const alias = this.nextAlias();
    const aliasPath = path ? `${path}.${alias}` : alias;
    const node = filterEmbed(alias, condition, condition.quantifier === "some");
    this.withPath(node.children, aliasPath);
    embeds.push(node);

    const where =
      condition.quantifier === "every" && condition.where
        ? ({ kind: "not", item: condition.where } as const)
        : condition.where;
    if (where) this.andContext(where, aliasPath, node.children);
    if (condition.quantifier !== "some") {
      this.filters.push({
        kind: "filter",
        path: aliasPath,
        operator: "is",
        value: "null",
      });
    }
  }

  /** Compiles a condition into a PostgREST logic-tree term. */
  logic(condition: Condition, embeds: EmbedNode[]): string {
    switch (condition.kind) {
      case "and":
      case "or":
        return `${condition.kind}(${condition.items
          .map((item) => this.logic(item, embeds))
          .join(",")})`;
      case "not": {
        const inner = condition.item;
        if (inner.kind === "column") {
          const { operator, value } = operatorAndValue(inner, true);
          return `${target(inner)}.not.${operator}.${value}`;
        }
        if (inner.kind === "relation") {
          return this.logic(negateRelation(inner), embeds);
        }
        if (inner.kind === "not") return this.logic(inner.item, embeds);
        return `not.${this.logic(inner, embeds)}`;
      }
      case "column": {
        const { operator, value } = operatorAndValue(condition, true);
        return `${target(condition)}.${operator}.${value}`;
      }
      case "relation": {
        if (condition.quantifier === "every" && !condition.where) {
          invalidRequest("every({}) must be simplified before compiling");
        }
        const alias = this.nextAlias();
        const node = filterEmbed(alias, condition, false);
        const nodePath = this.pathOf(alias, embeds);
        this.withPath(node.children, nodePath);
        embeds.push(node);
        const where =
          condition.quantifier === "every" && condition.where
            ? ({ kind: "not", item: condition.where } as const)
            : condition.where;
        // The embed's own filters are request parameters under the embed
        // path; only the null check goes in the logic tree.
        if (where) this.andContext(where, nodePath, node.children);
        return condition.quantifier === "some"
          ? `${alias}.not.is.null`
          : `${alias}.is.null`;
      }
      default: {
        const exhaustive: never = condition;
        return exhaustive;
      }
    }
  }

  // Filter embeds created from a logic tree hang off the current embed list;
  // their path is resolved by the caller that owns the list.
  readonly #paths = new WeakMap<EmbedNode[], string | undefined>();

  withPath(embeds: EmbedNode[], path: string | undefined): EmbedNode[] {
    this.#paths.set(embeds, path);
    return embeds;
  }

  private pathOf(alias: string, embeds: EmbedNode[]): string {
    const parent = this.#paths.get(embeds);
    return parent ? `${parent}.${alias}` : alias;
  }

  include(
    include: Include,
    path: string | undefined,
    embeds: EmbedNode[],
  ): void {
    const aliasPath = path ? `${path}.${include.alias}` : include.alias;
    const node: EmbedNode = {
      alias: include.alias,
      target: include.target,
      relation: include.relation,
      inner: include.required,
      columns: include.selection.columns,
      children: this.withPath([], aliasPath),
      ...(include.count === undefined ? {} : { count: true }),
      ...(include.selection.aggregate
        ? { measures: include.selection.aggregate.measures }
        : {}),
    };
    embeds.push(node);
    for (const child of include.selection.includes) {
      this.include(child, aliasPath, node.children);
    }
    const where = simplifyOrFalse(include.where);
    if (where.never) {
      // No related row can match: an impossible filter keeps the embed empty.
      const [first] = include.target.primaryKey;
      const column = first ? include.target.columns[first]?.db : undefined;
      if (!column)
        invalidRequest(`Cannot filter "${include.alias}" to nothing`);
      this.filters.push(
        {
          kind: "filter",
          path: `${aliasPath}.${column}`,
          operator: "is",
          value: "null",
        },
        {
          kind: "filter",
          path: `${aliasPath}.${column}`,
          operator: "not.is",
          value: "null",
        },
      );
    } else if (where.condition) {
      this.andContext(where.condition, aliasPath, node.children);
    }
    for (const term of include.orderBy) this.order(term, aliasPath);
    if (include.limit !== undefined) {
      this.limits.push({ count: include.limit, referencedTable: aliasPath });
    }
  }

  /**
   * Sorts the root rows by a column of a to-one embed, `order=alias(column)`.
   * Reuses the include of that relation, or adds an empty embed for it.
   */
  relationOrder(term: OrderTerm, embeds: EmbedNode[]): void {
    const { relation } = term;
    if (!relation) return;
    let alias = embeds.find(
      (node) =>
        node.relation.foreignKey === relation.relation.foreignKey &&
        node.target === relation.target &&
        node.count === undefined &&
        node.measures === undefined &&
        node.alias === relation.name,
    )?.alias;
    if (alias === undefined) {
      alias = this.nextAlias();
      embeds.push({
        alias,
        target: relation.target,
        relation: relation.relation,
        inner: false,
        columns: [],
        children: [],
      });
    }
    this.order({ ...term, column: `${alias}(${term.column})` }, undefined);
  }

  order(term: OrderTerm, referencedTable: string | undefined): void {
    this.orders.push({
      column: term.column,
      ascending: term.direction === "asc",
      nullsFirst: term.nulls === undefined ? undefined : term.nulls === "first",
      referencedTable,
    });
  }
}

function negateRelation(
  condition: Extract<Condition, { kind: "relation" }>,
): Extract<Condition, { kind: "relation" }> {
  switch (condition.quantifier) {
    case "some":
      return { ...condition, quantifier: "none" };
    case "none":
      return { ...condition, quantifier: "some" };
    case "every":
      return {
        ...condition,
        quantifier: "some",
        where: condition.where
          ? { kind: "not", item: condition.where }
          : undefined,
      };
    default: {
      const exhaustive: never = condition.quantifier;
      return exhaustive;
    }
  }
}

function filterEmbed(
  alias: string,
  condition: Extract<Condition, { kind: "relation" }>,
  inner: boolean,
): EmbedNode {
  return {
    alias,
    target: condition.target,
    relation: condition.relation,
    inner,
    columns: [],
    children: [],
  };
}

const columnTexts = new WeakMap<readonly SelectColumn[], string>();

/** The rendered column list, cached per (shared, immutable) column array. */
function columnText(columns: readonly SelectColumn[]): string {
  let text = columnTexts.get(columns);
  if (text === undefined) {
    text = columns
      .map(({ alias, column, cast }) => {
        const source = cast ? `${column}::${cast}` : column;
        return alias === column ? source : `${alias}:${source}`;
      })
      .join(",");
    columnTexts.set(columns, text);
  }
  return text;
}

function columnList(columns: readonly SelectColumn[]): string[] {
  return columns.length > 0 ? [columnText(columns)] : [];
}

/** `key:column.sum()::text`, PostgREST's aggregate syntax (PostgREST 12+). */
function measureList(measures: readonly Measure[]): string[] {
  return measures.map(
    ({ key, column, fn, cast }) =>
      `${key}:${column}.${fn}()${cast ? `::${cast}` : ""}`,
  );
}

function aggregateList(aggregate: Aggregation): string[] {
  return [
    ...(aggregate.count ? ["_count:count()"] : []),
    ...measureList(aggregate.measures),
  ];
}

function renderEmbeds(embeds: readonly EmbedNode[]): string[] {
  return embeds.map((node) => {
    const hint = `${node.target.name}!${node.relation.foreignKey}${node.inner ? "!inner" : ""}`;
    if (node.count) return `${node.alias}:${hint}(count)`;
    if (node.measures)
      return `${node.alias}:${hint}(${measureList(node.measures).join(",")})`;
    const inside = [
      ...columnList(node.columns),
      ...renderEmbeds(node.children),
    ];
    return `${node.alias}:${hint}(${inside.join(",")})`;
  });
}

function renderSelect(
  selection: Selection,
  embeds: readonly EmbedNode[],
): string {
  if (!selection.aggregate && embeds.length === 0)
    return selection.columns.length > 0 ? columnText(selection.columns) : "*";
  const parts = [
    ...columnList(selection.columns),
    ...(selection.aggregate ? aggregateList(selection.aggregate) : []),
    ...renderEmbeds(embeds),
  ];
  return parts.length > 0 ? parts.join(",") : "*";
}

function applyWhere(
  compiler: PostgrestCompiler,
  condition: Condition | undefined,
  embeds: EmbedNode[],
): boolean {
  const where = simplifyOrFalse(condition);
  if (where.never) return false;
  if (where.condition) compiler.andContext(where.condition, undefined, embeds);
  return true;
}

/** Compiles an operation into a PostgREST plan. */
export function compilePostgrest(op: Operation): PostgrestPlan {
  const compiler = new PostgrestCompiler();
  const embeds = compiler.withPath([], undefined);

  const selection =
    op.kind === "select"
      ? op.selection
      : op.kind === "insert"
        ? op.returning
        : op.returning;

  if (selection) {
    for (const include of selection.includes)
      compiler.include(include, undefined, embeds);
  }

  let matches = true;
  if (op.kind === "select" || op.kind === "update" || op.kind === "delete") {
    const before = embeds.length;
    matches = applyWhere(compiler, op.where, embeds);
    if (op.kind !== "select" && embeds.length > before) {
      invalidRequest(
        `Relation filters are not supported in ${op.kind} on PostgREST; filter by key instead`,
        op.table.key,
      );
    }
  }

  let range: PostgrestPlan["range"];
  if (op.kind === "select") {
    for (const term of op.orderBy) {
      if (term.relation) compiler.relationOrder(term, embeds);
      else compiler.order(term, undefined);
    }
    if (op.offset !== undefined) {
      const from = op.offset;
      const to =
        op.limit === undefined ? Number.MAX_SAFE_INTEGER : from + op.limit - 1;
      range = { from, to };
    } else if (op.limit !== undefined) {
      compiler.limits.push({ count: op.limit, referencedTable: undefined });
    }
  }

  return {
    select: selection ? renderSelect(selection, embeds) : undefined,
    filters: compiler.filters,
    orders: compiler.orders,
    limits: compiler.limits,
    range,
    never: !matches,
  };
}
