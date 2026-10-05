import type { Codec, RelationMeta, TableMeta } from "../schema/types.ts";

/**
 * The query IR. Every repository call becomes one of these operations; the
 * executor compiles it to PostgREST or SQL. Column names in the IR are
 * database names; `Selection` carries the app aliases.
 */
export type ColumnOp =
  | "eq"
  | "neq"
  | "gt"
  | "gte"
  | "lt"
  | "lte"
  | "in"
  | "is"
  | "like"
  | "ilike"
  | "contains"
  | "containedBy"
  | "overlaps"
  | "fts";

export type Quantifier = "some" | "none" | "every";

export type Condition =
  | { readonly kind: "and"; readonly items: readonly Condition[] }
  | { readonly kind: "or"; readonly items: readonly Condition[] }
  | { readonly kind: "not"; readonly item: Condition }
  | {
      readonly kind: "column";
      readonly column: string;
      readonly op: ColumnOp;
      readonly value: unknown;
      /** Full-text search configuration for `fts`. */
      readonly config?: string;
    }
  | {
      readonly kind: "relation";
      readonly name: string;
      readonly relation: RelationMeta;
      readonly target: TableMeta;
      readonly quantifier: Quantifier;
      readonly where: Condition | undefined;
    };

export interface SelectColumn {
  /** Key in the returned row. */
  readonly alias: string;
  /** Database column name. */
  readonly column: string;
  /** Read the column as text, so exact `int8`/`numeric` values survive JSON. */
  readonly cast?: "text";
  /** Decodes the returned value (see `ColumnMeta.codec`). */
  readonly codec?: Codec;
}

export interface OrderTerm {
  readonly column: string;
  readonly direction: "asc" | "desc";
  readonly nulls?: "first" | "last";
}

export interface Include {
  readonly alias: string;
  readonly relation: RelationMeta;
  readonly target: TableMeta;
  readonly selection: Selection;
  readonly where: Condition | undefined;
  readonly orderBy: readonly OrderTerm[];
  readonly limit: number | undefined;
  /** Drop parent rows without a match (`!inner`). */
  readonly required: boolean;
  /**
   * `_count` include: returns the number of matching related rows instead of
   * rows, folded into `row._count[count]` when decoded.
   */
  readonly count?: string;
  /**
   * `_sum`/`_avg`/`_min`/`_max` include: `selection.aggregate` holds the
   * measures, folded into `row[`_${fn}`][name]` when decoded.
   */
  readonly aggregate?: { readonly fn: AggregateFn; readonly name: string };
}

export type AggregateFn = "sum" | "avg" | "min" | "max";

export interface Measure {
  readonly fn: AggregateFn;
  /** Key in the returned row (`_sum_amount`, or the column alias in an include). */
  readonly key: string;
  /** App column name, the key under `_sum` in the decoded row. */
  readonly alias: string;
  /** Database column name. */
  readonly column: string;
  /** Read the result as text, so exact `int8`/`numeric` values survive JSON. */
  readonly cast?: "text";
  readonly codec?: Codec;
}

/**
 * Aggregates instead of rows. `Selection.columns` become the grouping
 * columns; without any, the result is exactly one row.
 */
export interface Aggregation {
  /** Also return `_count`, the number of rows in each group. */
  readonly count: boolean;
  readonly measures: readonly Measure[];
}

export interface Selection {
  readonly columns: readonly SelectColumn[];
  readonly includes: readonly Include[];
  readonly aggregate?: Aggregation;
}

export type CountMode = "exact" | "planned" | "estimated";

export interface SelectOp {
  readonly kind: "select";
  readonly table: TableMeta;
  readonly selection: Selection;
  readonly where: Condition | undefined;
  readonly orderBy: readonly OrderTerm[];
  readonly limit: number | undefined;
  readonly offset: number | undefined;
  readonly count: CountMode | undefined;
  /** Only count, return no rows. */
  readonly head: boolean;
  readonly single: "one" | "maybe" | undefined;
  /** `limit` includes one row past the page, which `paginate()` reads to set `hasMore`. */
  readonly lookAhead?: boolean;
  /**
   * Read from this set-returning function instead of the table (`db.$search`).
   * Only executors with `functionSources` honor it.
   */
  readonly source?: FunctionSource;
}

/** A function returning `setof <table>`, called with named arguments. */
export interface FunctionSource {
  readonly schema: string;
  readonly name: string;
  readonly args: Readonly<Record<string, unknown>>;
}

/** The statement a mutation runs. */
export type MutationKind = "insert" | "upsert" | "update" | "delete";

/** What the caller asked for: `softDelete` is a `delete` that a plugin turned into an update. */
export type MutationIntent = MutationKind | "softDelete";

interface MutationBase {
  /**
   * What the caller asked for, when a plugin rewrote the mutation into
   * another kind. The plugin that rewrites it sets this; mutation events
   * report it.
   */
  readonly intent?: MutationIntent;
}

export interface InsertOp extends MutationBase {
  readonly kind: "insert";
  readonly table: TableMeta;
  /** Rows keyed by database column names. */
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly returning: Selection | undefined;
  readonly onConflict:
    | {
        readonly columns: readonly string[];
        readonly action: "update" | "ignore";
      }
    | undefined;
  /** Missing columns become `null` instead of their default in bulk inserts. */
  readonly defaultToNull: boolean;
}

export interface UpdateOp extends MutationBase {
  readonly kind: "update";
  readonly table: TableMeta;
  /** Keyed by database column names. */
  readonly set: Readonly<Record<string, unknown>>;
  readonly where: Condition | undefined;
  readonly returning: Selection | undefined;
}

export interface DeleteOp extends MutationBase {
  readonly kind: "delete";
  readonly table: TableMeta;
  readonly where: Condition | undefined;
  readonly returning: Selection | undefined;
}

export type Operation = SelectOp | InsertOp | UpdateOp | DeleteOp;
export type MutationOp = InsertOp | UpdateOp | DeleteOp;

export const and = (
  ...items: (Condition | undefined)[]
): Condition | undefined => {
  const present = items.filter((item): item is Condition => item !== undefined);
  if (present.length === 0) return undefined;
  if (present.length === 1) return present[0];
  return { kind: "and", items: present };
};

export const or = (...items: Condition[]): Condition => {
  if (items.length === 1 && items[0]) return items[0];
  return { kind: "or", items };
};

export const not = (item: Condition): Condition => ({ kind: "not", item });

export const column = (
  name: string,
  op: ColumnOp,
  value: unknown,
): Condition => ({ kind: "column", column: name, op, value });
