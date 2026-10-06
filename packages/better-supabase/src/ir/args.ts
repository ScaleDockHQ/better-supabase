import type {
  AnyModels,
  Relations,
  RelationTypes,
  Row,
  Simplify,
} from "../schema/types.ts";

// ---------------------------------------------------------------------------
// Column filters

interface BaseOps<V> {
  readonly eq?: V;
  readonly neq?: V;
  readonly in?: readonly NonNullable<V>[];
  readonly notIn?: readonly NonNullable<V>[];
  readonly isNull?: boolean;
  readonly not?: FieldFilter<V>;
}

interface ComparableOps<V> {
  readonly gt?: V;
  readonly gte?: V;
  readonly lt?: V;
  readonly lte?: V;
}

interface TextOps {
  /** SQL LIKE pattern. `%` and `_` are wildcards. */
  readonly like?: string;
  /** Case-insensitive LIKE pattern. */
  readonly ilike?: string;
  /** POSIX regular expression (`~`). */
  readonly match?: string;
  /** Case-insensitive POSIX regular expression (`~*`). */
  readonly imatch?: string;
  /** Case-insensitive substring match; wildcards in the value are escaped. */
  readonly contains?: string;
  readonly startsWith?: string;
  readonly endsWith?: string;
  /** Full-text search (`websearch_to_tsquery`). */
  readonly search?:
    | string
    | { readonly query: string; readonly config?: string };
}

interface ArrayOps<E> {
  /** The array contains every given element. */
  readonly hasEvery?: readonly E[];
  /** The array shares at least one element with the given ones. */
  readonly hasSome?: readonly E[];
  /** The array contains the element. */
  readonly has?: E;
  /** The array is a subset of the given elements. */
  readonly containedBy?: readonly E[];
}

interface JsonOps<V> {
  /**
   * jsonb `@>`: the value contains the given structure. An array matches a
   * JSON array holding every given element (`[{ "type": "image" }]`).
   */
  readonly contains?: Partial<V> | Record<string, unknown> | readonly unknown[];
}

type JsonText = string | number | boolean;

/**
 * Compares the text at a path inside a json column (`column->a->>b`).
 * Numbers and booleans compare as their text; `isNull` and `eq: null` match a
 * missing key and JSON `null`.
 */
export interface JsonPathOps {
  /** Keys from the column down; a number-like key indexes an array. */
  readonly path: readonly [string, ...string[]];
  readonly eq?: JsonText | null;
  readonly neq?: JsonText | null;
  readonly in?: readonly JsonText[];
  readonly notIn?: readonly JsonText[];
  readonly isNull?: boolean;
  /** Text comparison, so `"10" < "9"`; store numbers you compare in a column. */
  readonly gt?: string;
  readonly gte?: string;
  readonly lt?: string;
  readonly lte?: string;
  readonly like?: string;
  readonly ilike?: string;
  readonly match?: string;
  readonly imatch?: string;
}

type OpsFor<V> = [NonNullable<V>] extends [string]
  ? BaseOps<V> & ComparableOps<V> & TextOps
  : [NonNullable<V>] extends [number | bigint]
    ? BaseOps<V> & ComparableOps<V>
    : [NonNullable<V>] extends [boolean]
      ? BaseOps<V>
      : [NonNullable<V>] extends [readonly (infer E)[]]
        ? BaseOps<V> & ArrayOps<E>
        : (BaseOps<V> & JsonOps<NonNullable<V>>) | JsonPathOps;

/** A value (equality, or `null` for `is null`) or an operator object. */
export type FieldFilter<V> = V | OpsFor<V>;

// ---------------------------------------------------------------------------
// Where

type RelationFilter<M extends AnyModels, R> = R extends {
  readonly table: infer X extends keyof M;
  readonly kind: "many";
}
  ? {
      /** At least one related row matches. `{}` means at least one exists. */
      readonly some?: WhereInput<M, X>;
      /** No related row matches. `{}` means none exist. */
      readonly none?: WhereInput<M, X>;
      /** Every related row matches (vacuously true without related rows). */
      readonly every?: WhereInput<M, X>;
    }
  : R extends {
        readonly table: infer X extends keyof M;
        readonly nullable: infer N;
      }
    ?
        | WhereInput<M, X>
        | (N extends true ? null : never)
        | {
            readonly is?: WhereInput<M, X> | (N extends true ? null : never);
            readonly isNot?: WhereInput<M, X> | (N extends true ? null : never);
          }
    : never;

export type WhereInput<M extends AnyModels, T extends keyof M> = {
  readonly [K in keyof Row<M, T>]?: FieldFilter<Row<M, T>[K]>;
} & {
  readonly [R in keyof Relations<M, T>]?: RelationFilter<M, Relations<M, T>[R]>;
} & {
  readonly AND?: WhereInput<M, T> | readonly WhereInput<M, T>[];
  readonly OR?: readonly WhereInput<M, T>[];
  readonly NOT?: WhereInput<M, T>;
};

// ---------------------------------------------------------------------------
// Ordering, selection, includes

export type SortDirection = "asc" | "desc";

export type SortSpec =
  | SortDirection
  | { readonly direction: SortDirection; readonly nulls?: "first" | "last" };

/** The columns of one table, each with a sort direction. */
export type ColumnOrderBy<M extends AnyModels, T extends keyof M> = {
  readonly [K in keyof Row<M, T>]?: SortSpec;
};

/**
 * Columns of the table, and of its to-one relations one level down:
 * `{ organization: { name: "asc" } }` sorts by the related row's name.
 */
export type OrderByInput<
  M extends AnyModels,
  T extends keyof M,
> = ColumnOrderBy<M, T> & {
  readonly [R in keyof Relations<M, T>]?: RelationOrderBy<
    M,
    Relations<M, T>[R]
  >;
};

type RelationOrderBy<M extends AnyModels, R> = R extends {
  readonly kind: "one";
  readonly table: infer X extends keyof M;
}
  ? ColumnOrderBy<M, X>
  : never;

export type OrderByArg<M extends AnyModels, T extends keyof M> =
  | OrderByInput<M, T>
  | readonly OrderByInput<M, T>[];

/** Sorts by the table's own columns only (includes, aggregates). */
export type ColumnOrderByArg<M extends AnyModels, T extends keyof M> =
  | ColumnOrderBy<M, T>
  | readonly ColumnOrderBy<M, T>[];

export type SelectArg<
  M extends AnyModels,
  T extends keyof M,
> = readonly Extract<keyof Row<M, T>, string>[];

export interface IncludeArgs<M extends AnyModels, T extends keyof M> {
  readonly select?: SelectArg<M, T>;
  readonly include?: IncludeArg<M, T>;
  readonly where?: WhereInput<M, T>;
  readonly orderBy?: ColumnOrderByArg<M, T>;
  readonly limit?: number;
  /** Only return parent rows that have a matching related row. */
  readonly required?: boolean;
}

export type IncludeArg<M extends AnyModels, T extends keyof M> = {
  readonly [R in keyof Relations<M, T>]?:
    | true
    | IncludeArgs<M, Extract<TargetOf<Relations<M, T>[R]>, keyof M>>;
} & {
  /** Counts related rows: `_count: { notes: true }` returns `_count.notes`. */
  readonly _count?: CountArg<M, T>;
} & {
  /**
   * Aggregates related rows: `_sum: { invoices: { amount: true } }` returns
   * `_sum.invoices.amount`. `_sum`/`_avg` need numeric columns.
   */
  readonly [K in MeasureKey]?: RelationMeasureArg<M, T>;
};

type NumericKey<M extends AnyModels, T extends keyof M> = {
  [K in keyof Row<M, T>]: [NonNullable<Row<M, T>[K]>] extends [
    number | bigint | string,
  ]
    ? K
    : never;
}[keyof Row<M, T>];

export type MeasureKey = "_sum" | "_avg" | "_min" | "_max";

/** Columns to aggregate: `{ amount: true }`. */
export type MeasureArg<M extends AnyModels, T extends keyof M> = {
  readonly [K in keyof Row<M, T>]?: true;
};

/** `_sum` and `_avg` take number (and numeric-as-string) columns only. */
export type NumericMeasureArg<M extends AnyModels, T extends keyof M> = {
  readonly [K in NumericKey<M, T>]?: true;
};

/** Relation aggregates check numeric columns at runtime, to keep includes cheap to type. */
export type RelationMeasureArg<M extends AnyModels, T extends keyof M> = {
  readonly [R in ManyRelations<M, T>]?: MeasureArg<
    M,
    Extract<TargetOf<Relations<M, T>[R]>, keyof M>
  >;
};

type ManyRelations<M extends AnyModels, T extends keyof M> = {
  [R in keyof Relations<M, T>]: Relations<M, T>[R] extends {
    readonly kind: "many";
  }
    ? R
    : never;
}[keyof Relations<M, T>];

export type CountArg<M extends AnyModels, T extends keyof M> = {
  readonly [R in ManyRelations<M, T>]?:
    | true
    | {
        readonly where?: WhereInput<
          M,
          Extract<TargetOf<Relations<M, T>[R]>, keyof M>
        >;
      };
};

type TargetOf<R> = R extends { readonly table: infer X } ? X : never;

export interface ReadArgs<M extends AnyModels, T extends keyof M> {
  readonly select?: SelectArg<M, T>;
  readonly include?: IncludeArg<M, T>;
  readonly signal?: AbortSignal;
}

export interface FindManyArgs<
  M extends AnyModels,
  T extends keyof M,
> extends ReadArgs<M, T> {
  readonly where?: WhereInput<M, T>;
  readonly orderBy?: OrderByArg<M, T>;
  readonly limit?: number;
  readonly offset?: number;
}

export type FindFirstArgs<M extends AnyModels, T extends keyof M> = Omit<
  FindManyArgs<M, T>,
  "limit"
>;

export interface CountArgs<M extends AnyModels, T extends keyof M> {
  readonly where?: WhereInput<M, T>;
  readonly mode?: "exact" | "planned" | "estimated";
  readonly signal?: AbortSignal;
}

export interface AggregateArgs<M extends AnyModels, T extends keyof M> {
  readonly where?: WhereInput<M, T>;
  /** One result per distinct combination; without it, one result. */
  readonly groupBy?: SelectArg<M, T>;
  /** The number of rows (per group). */
  readonly _count?: true;
  readonly _sum?: NumericMeasureArg<M, T>;
  readonly _avg?: NumericMeasureArg<M, T>;
  readonly _min?: MeasureArg<M, T>;
  readonly _max?: MeasureArg<M, T>;
  /** Sorts groups; only `groupBy` columns. */
  readonly orderBy?: ColumnOrderByArg<M, T>;
  readonly limit?: number;
  readonly offset?: number;
  readonly signal?: AbortSignal;
}

// ---------------------------------------------------------------------------
// Result payloads

type SelectPart<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly select: readonly (infer K)[];
}
  ? Pick<Row<M, T>, Extract<K, keyof Row<M, T>>>
  : Row<M, T>;

type RelationPayload<M extends AnyModels, R, V> = R extends RelationTypes
  ? R["kind"] extends "many"
    ? Payload<M, Extract<R["table"], keyof M>, V extends true ? unknown : V>[]
    : R["nullable"] extends true
      ? Payload<
          M,
          Extract<R["table"], keyof M>,
          V extends true ? unknown : V
        > | null
      : Payload<M, Extract<R["table"], keyof M>, V extends true ? unknown : V>
  : never;

type IncludePart<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly include: infer I;
}
  ? {
      -readonly [R in keyof I & keyof Relations<M, T>]: RelationPayload<
        M,
        Relations<M, T>[R],
        I[R]
      >;
    } & CountPart<I> &
      ([keyof I & MeasureKey] extends [never]
        ? unknown
        : RelationMeasures<M, T, I>)
  : unknown;

type CountPart<I> = I extends { readonly _count: infer C }
  ? { _count: { -readonly [R in keyof C]: number } }
  : unknown;

/**
 * `_avg` is a number; `_sum` keeps exact `bigint` and `string` (numeric)
 * columns; `_min`/`_max` have the column's type. All are `null` without rows.
 */
type MeasureValue<K extends MeasureKey, V> = K extends "_avg"
  ? number | null
  : K extends "_sum"
    ? [NonNullable<V>] extends [bigint]
      ? bigint | null
      : [NonNullable<V>] extends [string]
        ? string | null
        : number | null
    : NonNullable<V> | null;

type MeasuresOf<
  M extends AnyModels,
  T extends keyof M,
  C,
  K extends MeasureKey,
> = {
  -readonly [P in keyof C & keyof Row<M, T>]: MeasureValue<K, Row<M, T>[P]>;
};

type RelationMeasures<M extends AnyModels, T extends keyof M, I> = {
  -readonly [K in keyof I & MeasureKey]: {
    -readonly [R in keyof I[K] & keyof Relations<M, T>]: MeasuresOf<
      M,
      Extract<TargetOf<Relations<M, T>[R]>, keyof M>,
      I[K][R],
      K
    >;
  };
};

type RootMeasures<
  M extends AnyModels,
  T extends keyof M,
  A,
  K extends MeasureKey,
> = A extends { readonly [P in K]: infer C }
  ? { [P in K]: MeasuresOf<M, T, C, K> }
  : unknown;

/** One aggregate result: the `groupBy` columns, `_count` and each measure. */
export type AggregateRow<M extends AnyModels, T extends keyof M, A> = Simplify<
  (A extends { readonly groupBy: readonly (infer K)[] }
    ? Pick<Row<M, T>, Extract<K, keyof Row<M, T>>>
    : unknown) &
    (A extends { readonly _count: true } ? { _count: number } : unknown) &
    RootMeasures<M, T, A, "_sum"> &
    RootMeasures<M, T, A, "_avg"> &
    RootMeasures<M, T, A, "_min"> &
    RootMeasures<M, T, A, "_max">
>;

/** `aggregate()` returns one row per group with `groupBy`, else one row. */
export type AggregateResult<
  M extends AnyModels,
  T extends keyof M,
  A,
> = A extends { readonly groupBy: readonly unknown[] }
  ? AggregateRow<M, T, A>[]
  : AggregateRow<M, T, A>;

/** The row type returned for read arguments `A` on table `T`. */
export type Payload<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly include: unknown;
}
  ? Simplify<SelectPart<M, T, A> & IncludePart<M, T, A>>
  : A extends { readonly select: readonly unknown[] }
    ? Simplify<SelectPart<M, T, A>>
    : Row<M, T>;
