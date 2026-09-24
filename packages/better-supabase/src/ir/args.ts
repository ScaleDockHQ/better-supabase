import type {
  AnyModels,
  Relations,
  RelationShape,
  Row,
  Simplify,
} from '../schema/types.ts';

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
  /** jsonb `@>`: the value contains the given structure. */
  readonly contains?: Partial<V> | Record<string, unknown>;
}

type OpsFor<V> = [NonNullable<V>] extends [string]
  ? BaseOps<V> & ComparableOps<V> & TextOps
  : [NonNullable<V>] extends [number | bigint]
    ? BaseOps<V> & ComparableOps<V>
    : [NonNullable<V>] extends [boolean]
      ? BaseOps<V>
      : [NonNullable<V>] extends [readonly (infer E)[]]
        ? BaseOps<V> & ArrayOps<E>
        : BaseOps<V> & JsonOps<NonNullable<V>>;

/** A value (equality, or `null` for `is null`) or an operator object. */
export type FieldFilter<V> = V | OpsFor<V>;

// ---------------------------------------------------------------------------
// Where

type RelationFilter<M extends AnyModels, R> = R extends {
  readonly table: infer X extends keyof M;
  readonly kind: 'many';
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

export type SortDirection = 'asc' | 'desc';

export type OrderByInput<M extends AnyModels, T extends keyof M> = {
  readonly [K in keyof Row<M, T>]?:
    | SortDirection
    | { readonly direction: SortDirection; readonly nulls?: 'first' | 'last' };
};

export type OrderByArg<M extends AnyModels, T extends keyof M> =
  | OrderByInput<M, T>
  | readonly OrderByInput<M, T>[];

export type SelectArg<
  M extends AnyModels,
  T extends keyof M,
> = readonly Extract<keyof Row<M, T>, string>[];

export interface IncludeArgs<M extends AnyModels, T extends keyof M> {
  readonly select?: SelectArg<M, T>;
  readonly include?: IncludeArg<M, T>;
  readonly where?: WhereInput<M, T>;
  readonly orderBy?: OrderByArg<M, T>;
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
};

type ManyRelations<M extends AnyModels, T extends keyof M> = {
  [R in keyof Relations<M, T>]: Relations<M, T>[R] extends {
    readonly kind: 'many';
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
  'limit'
>;

export interface CountArgs<M extends AnyModels, T extends keyof M> {
  readonly where?: WhereInput<M, T>;
  readonly mode?: 'exact' | 'planned' | 'estimated';
  readonly signal?: AbortSignal;
}

// ---------------------------------------------------------------------------
// Result payloads

type SelectPart<M extends AnyModels, T extends keyof M, A> = A extends {
  readonly select: readonly (infer K)[];
}
  ? Pick<Row<M, T>, Extract<K, keyof Row<M, T>>>
  : Row<M, T>;

type RelationPayload<M extends AnyModels, R, V> = R extends RelationShape
  ? R['kind'] extends 'many'
    ? Payload<M, Extract<R['table'], keyof M>, V extends true ? unknown : V>[]
    : R['nullable'] extends true
      ? Payload<
          M,
          Extract<R['table'], keyof M>,
          V extends true ? unknown : V
        > | null
      : Payload<M, Extract<R['table'], keyof M>, V extends true ? unknown : V>
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
    } & CountPart<I>
  : unknown;

type CountPart<I> = I extends { readonly _count: infer C }
  ? { _count: { -readonly [R in keyof C]: number } }
  : unknown;

/** The row type returned for read arguments `A` on table `T`. */
export type Payload<M extends AnyModels, T extends keyof M, A> = Simplify<
  SelectPart<M, T, A> & IncludePart<M, T, A>
>;
