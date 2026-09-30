export type Casing = 'snake' | 'camel';

/** Runtime metadata for one column. Keyed by the app (cased) column name. */
export interface ColumnMeta {
  /** Database column name. */
  readonly db: string;
  /** Postgres type name (`uuid`, `text`, `timestamptz`, `note_kind`). */
  readonly type: string;
  readonly nullable: boolean;
  readonly hasDefault: boolean;
  readonly generated?: boolean;
  /** Identity column; `'always'` columns can't be written. */
  readonly identity?: 'always' | 'by default';
  /** `false` when inserts can't set this column (generated, identity always, view). */
  readonly insertable?: false;
  /** `false` when updates can't set this column. */
  readonly updatable?: false;
  readonly array?: boolean;
  readonly json?: boolean;
  /** Allowed values for enum columns and CHECK-constraint unions. */
  readonly enum?: readonly string[];
  /** How values are decoded from the wire (see the `codecs` config). */
  readonly codec?: Codec;
  /** Listed in `config.sensitive`; the `noSensitiveSelect` rule guards reads of it. */
  readonly sensitive?: true;
  /** Bucket id of the objects this text column points to (`config.storagePaths`). */
  readonly storage?: string;
}

/**
 * Runtime representation for a column: `date` decodes timestamps to `Date`,
 * `bigint` and `string` read the exact text of `int8`/`numeric` values.
 */
export type Codec = 'date' | 'bigint' | 'string';

export interface RelationMeta {
  /** App key of the target table. */
  readonly table: string;
  readonly kind: 'one' | 'many';
  readonly nullable: boolean;
  /** Foreign key constraint name, used as the PostgREST embed hint. */
  readonly foreignKey: string;
  /** App column names on the source table. */
  readonly columns: readonly string[];
  /** App column names on the target table. */
  readonly references: readonly string[];
  /** `forward`: this table holds the FK. `reverse`: the target holds it. */
  readonly direction: 'forward' | 'reverse';
  /** What deleting the referenced row does to the referencing rows, when it changes them. */
  readonly onDelete?: 'cascade' | 'set null' | 'set default';
}

export interface TableFlags {
  /** App column holding the soft-delete timestamp. */
  readonly softDelete?: string;
  readonly timestamps?: {
    readonly createdAt?: string;
    readonly updatedAt?: string;
  };
  /** App column holding the tenant id. */
  readonly tenant?: string;
  readonly actor?: { readonly createdBy?: string; readonly updatedBy?: string };
  /** App column used for optimistic concurrency, usually `updatedAt`. */
  readonly version?: string;
}

export interface TableMeta {
  /** App key of the table (`customerTags` in camel casing). */
  readonly key: string;
  /** Database table name. */
  readonly name: string;
  readonly schema: string;
  readonly kind: 'table' | 'view';
  readonly columns: Readonly<Record<string, ColumnMeta>>;
  /** App column names. */
  readonly primaryKey: readonly string[];
  /** Constraint name to app column names. */
  readonly uniqueKeys: Readonly<Record<string, readonly string[]>>;
  readonly relations: Readonly<Record<string, RelationMeta>>;
  readonly flags: TableFlags;
}

export interface FunctionMeta {
  readonly name: string;
  readonly schema: string;
  readonly args: readonly { readonly name: string; readonly type: string }[];
  readonly returns: string;
  readonly returnsSet: boolean;
  readonly volatility: 'immutable' | 'stable' | 'volatile';
}

export interface SchemaMeta {
  readonly version: 1;
  readonly casing: Casing;
  readonly tables: Readonly<Record<string, TableMeta>>;
  readonly enums: Readonly<Record<string, readonly string[]>>;
  readonly functions: Readonly<Record<string, FunctionMeta>>;
  readonly buckets?: Readonly<Record<string, BucketMeta>>;
  readonly topics?: Readonly<Record<string, string>>;
  /** Tables that broadcast change signals (`config.realtime.tables`), keyed by app key. */
  readonly realtime?: Readonly<Record<string, RealtimeTableMeta>>;
  /** Claim names from `config.claims` that differ from the defaults. */
  readonly claims?: Partial<ClaimsMeta>;
}

/** The claim names the SQL kit, codegen and runtime defaults agree on. */
export interface ClaimsMeta {
  /** Top-level claim holding the active tenant id. Defaults to `tenant_id`. */
  readonly tenant: string;
  /** `scope` of the tenant entries in the `memberships` claim. Defaults to `tenant`. */
  readonly scope: string;
  /** Claim holding plan features per tenant (`{ [tenantId]: string[] }`). Defaults to `features`. */
  readonly features: string;
}

export interface RealtimeTableMeta {
  /** App column whose value scopes the broadcast topic. */
  readonly tenant?: string;
}

/**
 * Storage policies that call PermDock's generated SQL helpers:
 * `<schema>.permitted_<scope>_ids(key)` for a scope keyed by a path segment,
 * `<schema>.permdock_has(key)` for `scope: 'global'`. Only for permissions
 * whose grants have no row conditions beyond the scope.
 */
export interface PermdockBucketPolicy {
  readonly permdock: {
    /** Downloads, signed URLs, renders and metadata reads. */
    readonly read: string;
    /** Listing; without it `read` covers listing too. */
    readonly list?: string;
    /** Uploads, updates and moves; also deletes unless `delete` is set. */
    readonly write: string;
    readonly delete?: string;
  };
  /** A PermDock scope such as `organization`, or `global`. */
  readonly scope: string;
  /** 1-based path segment holding the scope id. Defaults to the `{orgId}` segment. */
  readonly segment?: number;
  /**
   * Schema of the helpers `permdock rls generate` writes: PermDock's
   * `rls.schema`. Defaults to `public`.
   */
  readonly schema?: string;
}

/** A PermDock topic policy: `select` (receive) and `insert` (send) on `realtime.messages`. */
export interface PermdockTopicPolicy {
  readonly receive: string;
  /** Lets clients send on the topic with this permission. */
  readonly send?: string;
  /** A PermDock scope such as `organization`, or `global`. */
  readonly scope: string;
  /** 1-based `:`-separated topic segment holding the scope id. Defaults to the `{orgId}` segment. */
  readonly segment?: number;
  readonly schema?: string;
}

export type BucketPolicyName = 'tenant' | 'owner' | 'public' | 'none';

export interface BucketMeta {
  readonly id: string;
  readonly public: boolean;
  readonly path: string;
  readonly policy?: BucketPolicyName | PermdockBucketPolicy;
  /** Claim paths for the tenant policy, when `config.claims.tenant` is not the default. */
  readonly tenant?: { readonly claim: readonly string[] };
  readonly fileSizeLimit?: string;
  readonly allowedMimeTypes?: readonly string[];
}

// ---------------------------------------------------------------------------
// Type-level model shapes, written as literal types by `better-supabase gen`.

export interface RelationShape {
  readonly table: string;
  readonly kind: 'one' | 'many';
  readonly nullable: boolean;
}

export interface FlagsShape {
  readonly softDelete?: string;
  readonly timestamps?: true;
  readonly tenant?: string;
  readonly actor?: true;
  readonly version?: string;
}

export interface ModelShape {
  readonly Row: object;
  readonly Insert: object;
  readonly Update: object;
  readonly Relations: object;
  readonly PrimaryKey: PropertyKey;
  readonly UniqueKeys: object;
  /** CHECK constraint names. */
  readonly Checks?: string;
  /** Foreign key constraint names on this table. */
  readonly ForeignKeys?: string;
  readonly Flags: FlagsShape;
}

export type AnyModels = { readonly [table: string]: ModelShape };

export type FunctionShape = {
  readonly Args: object;
  readonly Returns: unknown;
};
export type AnyFunctions = { readonly [name: string]: FunctionShape };

/**
 * Carries the model types next to the runtime metadata. Created by
 * `defineSchema` in the generated module.
 */
export interface Schema<
  M extends AnyModels = AnyModels,
  D = unknown,
  F extends AnyFunctions = AnyFunctions,
> {
  readonly meta: SchemaMeta;
  /** Phantom. Never present at runtime. */
  readonly '~types'?: {
    readonly models: M;
    readonly database: D;
    readonly functions: F;
  };
}

export type ModelsOf<S> = S extends Schema<infer M> ? M : never;
export type DatabaseOf<S> = S extends Schema<AnyModels, infer D> ? D : never;
export type FunctionsOf<S> =
  S extends Schema<AnyModels, unknown, infer F> ? F : never;

export type TableKey<M extends AnyModels> = Extract<keyof M, string>;
export type Row<M extends AnyModels, T extends keyof M> = M[T]['Row'];
export type Insert<M extends AnyModels, T extends keyof M> = M[T]['Insert'];
export type Update<M extends AnyModels, T extends keyof M> = M[T]['Update'];
export type Relations<
  M extends AnyModels,
  T extends keyof M,
> = M[T]['Relations'];
export type Flags<M extends AnyModels, T extends keyof M> = M[T]['Flags'];
export type PrimaryKeyColumn<M extends AnyModels, T extends keyof M> = Extract<
  M[T]['PrimaryKey'],
  keyof Row<M, T>
>;
export type UniqueKeyName<M extends AnyModels, T extends keyof M> = Extract<
  keyof M[T]['UniqueKeys'],
  string
>;

type UniqueKeyColumns<
  M extends AnyModels,
  T extends keyof M,
  K extends keyof M[T]['UniqueKeys'],
> = Extract<
  M[T]['UniqueKeys'][K] extends readonly (infer C)[] ? C : never,
  keyof Row<M, T>
>;

/**
 * Values for exactly one unique key: the primary key columns, or the columns
 * of one named unique constraint or unique index.
 */
export type UniqueWhere<M extends AnyModels, T extends keyof M> =
  | { readonly [C in PrimaryKeyColumn<M, T>]: Row<M, T>[C] }
  | {
      [K in keyof M[T]['UniqueKeys']]: {
        readonly [C in UniqueKeyColumns<M, T, K>]: Row<M, T>[C];
      };
    }[keyof M[T]['UniqueKeys']];

/** Every unique constraint name in the schema, for `isConflict`. */
export type UniqueConstraint<M extends AnyModels> = {
  [T in keyof M]: Extract<keyof M[T]['UniqueKeys'], string>;
}[keyof M];

/** Every CHECK constraint name in the schema, for `isCheck`. */
export type CheckConstraint<M extends AnyModels> = {
  [T in keyof M]: M[T] extends { readonly Checks: infer C extends string }
    ? C
    : never;
}[keyof M];

/** Every foreign key constraint name in the schema, for `isForeignKey`. */
export type ForeignKeyConstraint<M extends AnyModels> = {
  [T in keyof M]: M[T] extends { readonly ForeignKeys: infer C extends string }
    ? C
    : never;
}[keyof M];

type IsUnion<T, U = T> = T extends unknown
  ? [U] extends [T]
    ? false
    : true
  : never;

/** A single value for single-column keys, an object for composite keys. */
export type PrimaryKeyValue<M extends AnyModels, T extends keyof M> =
  true extends IsUnion<PrimaryKeyColumn<M, T>>
    ? { readonly [K in PrimaryKeyColumn<M, T>]: Row<M, T>[K] }
    : Row<M, T>[PrimaryKeyColumn<M, T>];

export type Simplify<T> = { [K in keyof T]: T[K] } & {};
