import type { GeneratorMetadata } from './typegen.ts';

export type { GeneratorMetadata };

/**
 * What `better-supabase introspect` reads from Postgres. `generator` is the
 * `@supabase/postgrest-typegen` contract (the same metadata behind
 * `supabase gen types`); `extras` holds what that contract leaves out.
 * Codegen and doctor both work from this snapshot, so either can run offline
 * from a saved file.
 */
export interface Snapshot {
  readonly $schema?: string;
  readonly version: 2;
  /** Every schema that was read, including helper schemas for doctor. */
  readonly schemas: readonly string[];
  readonly generator: GeneratorMetadata;
  readonly extras: SnapshotExtras;
}

/** Catalog details `GeneratorMetadata` does not carry. */
export interface SnapshotExtras {
  readonly tables: readonly ExtrasTable[];
  readonly buckets: readonly SnapshotBucket[];
  /** Tables in the `supabase_realtime` publication, as `schema.table`. */
  readonly realtime: readonly string[];
  /**
   * `alter role ... set` values for the Data API roles (`authenticator`),
   * such as `pgrst.db_aggregates_enabled`. Absent in older snapshots.
   */
  readonly roleSettings?: Readonly<
    Record<string, Readonly<Record<string, string>>>
  >;
  /**
   * Functions that policies in the read schemas call, plus functions in
   * those schemas with `set` options. Absent in older snapshots.
   */
  readonly functions?: readonly ExtrasFunction[];
  /**
   * The Postgres functions `supabase/config.toml` configures as Auth hooks,
   * in any schema. Absent in older snapshots and without a `config.toml`.
   */
  readonly hooks?: readonly ExtrasHook[];
}

/** An `[auth.hook.<name>]` with a `pg-functions://` URI. */
export interface ExtrasHook {
  /** `custom_access_token`, `send_email`, ... */
  readonly hook: string;
  readonly schema: string;
  readonly name: string;
  /** Every overload with that name; empty when the function does not exist. */
  readonly functions: readonly ExtrasHookFunction[];
}

export interface ExtrasHookFunction extends ExtrasFunction {
  /**
   * Of `supabase_auth_admin`, `authenticated` and `anon`, the roles that may
   * execute it (directly or through `public`).
   */
  readonly execute: readonly string[];
  /** Whether `public` may execute it (the default until revoked). */
  readonly publicExecute: boolean;
  /** Of the same roles, those with `usage` on its schema. */
  readonly schemaUsage: readonly string[];
}

/** A function as doctor needs it for RLS checks, in any schema. */
export interface ExtrasFunction {
  readonly schema: string;
  readonly name: string;
  /** Identity arguments, e.g. `org uuid`. */
  readonly signature: string;
  /** `sql`, `plpgsql`, `c`, ... */
  readonly language: string;
  readonly volatility: 'immutable' | 'stable' | 'volatile';
  readonly securityDefiner: boolean;
  /** `set` options, e.g. `{ statement_timeout: '5s' }`. */
  readonly settings: Readonly<Record<string, string>>;
}

export interface ExtrasTable {
  /** Table oid, matching `GeneratorMetadata.tables[].id`. */
  readonly id: number;
  readonly schema: string;
  readonly name: string;
  /** Primary key columns in key order. */
  readonly primaryKey: readonly string[];
  readonly uniques: readonly CatalogUnique[];
  readonly foreignKeys: readonly {
    readonly name: string;
    readonly onDelete: ForeignKeyAction;
    readonly onUpdate: ForeignKeyAction;
  }[];
  readonly checks: readonly CatalogCheck[];
  readonly indexes: readonly CatalogIndex[];
  readonly policies: readonly CatalogPolicy[];
  readonly triggers: readonly CatalogTrigger[];
  readonly grants: readonly CatalogGrant[];
}

export type ForeignKeyAction =
  | 'no action'
  | 'restrict'
  | 'cascade'
  | 'set null'
  | 'set default';

export interface CatalogUnique {
  readonly name: string;
  readonly columns: readonly string[];
}

export interface CatalogCheck {
  readonly name: string;
  readonly definition: string;
}

export interface CatalogIndex {
  readonly name: string;
  readonly columns: readonly string[];
  readonly unique: boolean;
  readonly primary: boolean;
  readonly partial: boolean;
}

export interface CatalogPolicy {
  readonly name: string;
  readonly command: 'all' | 'select' | 'insert' | 'update' | 'delete';
  readonly roles: readonly string[];
  readonly permissive: boolean;
  readonly using: string | null;
  readonly check: string | null;
  /**
   * Functions the policy expressions call, as `schema.name`, from
   * `pg_depend`. Absent in older snapshots.
   */
  readonly functions?: readonly string[];
}

export interface CatalogTrigger {
  readonly name: string;
  readonly timing: 'before' | 'after' | 'instead of';
  readonly events: readonly ('insert' | 'update' | 'delete' | 'truncate')[];
  readonly level: 'row' | 'statement';
  readonly function: string;
}

export interface CatalogGrant {
  readonly role: string;
  readonly privileges: readonly string[];
}

export interface SnapshotBucket {
  readonly id: string;
  readonly public: boolean;
  readonly fileSizeLimit: number | null;
  readonly allowedMimeTypes: readonly string[] | null;
}

/**
 * The snapshot joined into one record per table, function and enum. Codegen
 * and doctor read this view rather than the raw snapshot.
 */
export interface Catalog {
  readonly schemas: readonly string[];
  readonly tables: readonly CatalogTable[];
  readonly enums: readonly CatalogEnum[];
  readonly functions: readonly CatalogFunction[];
  readonly buckets: readonly SnapshotBucket[];
  readonly realtime: readonly string[];
}

export interface CatalogTable {
  readonly id: number;
  readonly schema: string;
  readonly name: string;
  /** Materialized views count as views; foreign tables as tables. */
  readonly kind: 'table' | 'view';
  readonly rls: boolean;
  readonly forceRls: boolean;
  readonly replicaIdentity: 'DEFAULT' | 'INDEX' | 'FULL' | 'NOTHING' | null;
  /** Inserts work (always true for tables). */
  readonly insertable: boolean;
  /** Updates work (always true for tables). */
  readonly updatable: boolean;
  readonly comment: string | null;
  readonly columns: readonly CatalogColumn[];
  readonly primaryKey: readonly string[];
  readonly uniques: readonly CatalogUnique[];
  readonly foreignKeys: readonly CatalogForeignKey[];
  readonly checks: readonly CatalogCheck[];
  readonly indexes: readonly CatalogIndex[];
  readonly policies: readonly CatalogPolicy[];
  readonly triggers: readonly CatalogTrigger[];
  readonly grants: readonly CatalogGrant[];
}

export interface CatalogColumn {
  readonly name: string;
  /** Type name; the element type for arrays (`uuid`, `int8`, `note_kind`). */
  readonly udt: string;
  /** Raw type name as Postgres reports it (`_text` for `text[]`). */
  readonly format: string;
  readonly typeSchema: string;
  readonly isArray: boolean;
  readonly isEnum: boolean;
  readonly nullable: boolean;
  readonly hasDefault: boolean;
  readonly default: string | null;
  readonly identity: 'always' | 'by default' | null;
  readonly generated: boolean;
  readonly updatable: boolean;
  readonly comment: string | null;
}

export interface CatalogForeignKey {
  readonly name: string;
  readonly columns: readonly string[];
  readonly refSchema: string;
  readonly refTable: string;
  readonly refColumns: readonly string[];
  readonly oneToOne: boolean;
  readonly onDelete: ForeignKeyAction;
  readonly onUpdate: ForeignKeyAction;
}

export interface CatalogEnum {
  readonly schema: string;
  readonly name: string;
  readonly values: readonly string[];
}

export interface CatalogFunction {
  readonly schema: string;
  readonly name: string;
  /** Signature that tells overloads apart, e.g. `a integer, b text`. */
  readonly signature: string;
  readonly args: readonly CatalogFunctionArg[];
  /** Columns for `returns table (...)` functions. */
  readonly returnsTable:
    | readonly { readonly name: string; readonly udt: string }[]
    | null;
  /** Return type name (`int4`, `_text`, a table's row type). */
  readonly returns: string;
  /** `schema.table` when the function returns rows of a table or view. */
  readonly returnsRelation: string | null;
  readonly returnsSet: boolean;
  readonly volatility: 'immutable' | 'stable' | 'volatile';
  readonly securityDefiner: boolean;
  readonly language: string;
  /** `search_path` from `SET search_path`, or `null` when unset. */
  readonly searchPath: string | null;
}

export interface CatalogFunctionArg {
  readonly name: string;
  readonly udt: string;
  readonly isArray: boolean;
  readonly hasDefault: boolean;
}
