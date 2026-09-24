import type { Codec, RelationMeta, TableMeta } from '../schema/types.ts';

/**
 * The query IR. Every repository call becomes one of these operations; the
 * executor compiles it to PostgREST or SQL. Column names in the IR are
 * database names; `Selection` carries the app aliases.
 */
export type ColumnOp =
  | 'eq'
  | 'neq'
  | 'gt'
  | 'gte'
  | 'lt'
  | 'lte'
  | 'in'
  | 'is'
  | 'like'
  | 'ilike'
  | 'contains'
  | 'containedBy'
  | 'overlaps'
  | 'fts';

export type Quantifier = 'some' | 'none' | 'every';

export type Condition =
  | { readonly kind: 'and'; readonly items: readonly Condition[] }
  | { readonly kind: 'or'; readonly items: readonly Condition[] }
  | { readonly kind: 'not'; readonly item: Condition }
  | {
      readonly kind: 'column';
      readonly column: string;
      readonly op: ColumnOp;
      readonly value: unknown;
      /** Full-text search configuration for `fts`. */
      readonly config?: string;
    }
  | {
      readonly kind: 'relation';
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
  readonly cast?: 'text';
  /** Decodes the returned value (see `ColumnMeta.codec`). */
  readonly codec?: Codec;
}

export interface OrderTerm {
  readonly column: string;
  readonly direction: 'asc' | 'desc';
  readonly nulls?: 'first' | 'last';
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
}

export interface Selection {
  readonly columns: readonly SelectColumn[];
  readonly includes: readonly Include[];
}

export type CountMode = 'exact' | 'planned' | 'estimated';

export interface SelectOp {
  readonly kind: 'select';
  readonly table: TableMeta;
  readonly selection: Selection;
  readonly where: Condition | undefined;
  readonly orderBy: readonly OrderTerm[];
  readonly limit: number | undefined;
  readonly offset: number | undefined;
  readonly count: CountMode | undefined;
  /** Only count, return no rows. */
  readonly head: boolean;
  readonly single: 'one' | 'maybe' | undefined;
}

export interface InsertOp {
  readonly kind: 'insert';
  readonly table: TableMeta;
  /** Rows keyed by database column names. */
  readonly rows: readonly Readonly<Record<string, unknown>>[];
  readonly returning: Selection | undefined;
  readonly onConflict:
    | {
        readonly columns: readonly string[];
        readonly action: 'update' | 'ignore';
      }
    | undefined;
  /** Missing columns become `null` instead of their default in bulk inserts. */
  readonly defaultToNull: boolean;
}

export interface UpdateOp {
  readonly kind: 'update';
  readonly table: TableMeta;
  /** Keyed by database column names. */
  readonly set: Readonly<Record<string, unknown>>;
  readonly where: Condition | undefined;
  readonly returning: Selection | undefined;
}

export interface DeleteOp {
  readonly kind: 'delete';
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
  return { kind: 'and', items: present };
};

export const or = (...items: Condition[]): Condition => {
  if (items.length === 1 && items[0]) return items[0];
  return { kind: 'or', items };
};

export const not = (item: Condition): Condition => ({ kind: 'not', item });

export const column = (
  name: string,
  op: ColumnOp,
  value: unknown,
): Condition => ({ kind: 'column', column: name, op, value });
