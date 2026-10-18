import type { Casing, SchemaMeta } from "../../schema/types.ts";
import type { GeneratorMetadata, SnapshotExtras } from ".././snapshot.ts";
import type { ResolvedConfig } from "./config.ts";

export type { Casing };

/**
 * Where codegen reads the database from. Without any of these, `$DATABASE_URL`,
 * `$SUPABASE_DB_URL` and then the local stack (`supabase start`) are used.
 */
export interface SourceConfig {
  /** Postgres connection string. */
  readonly dbUrl?: string;
  /**
   * Hosted project ref. Read through the Management API's read-only SQL
   * endpoint, so no database password is needed.
   */
  readonly projectRef?: string;
  /**
   * Management API token for `projectRef`. Defaults to
   * `$SUPABASE_ACCESS_TOKEN`; prefer the env var over committing a token.
   */
  readonly accessToken?: string;
  /** Read a saved `better-supabase introspect` snapshot instead of connecting. */
  readonly snapshot?: string;
  /**
   * Read a Supabase Lite project's schema the way Lite runs it, from
   * `[db] driver` in `supabase/config.toml`. On by default when that key is
   * present; `false` reads the database like any other project.
   */
  readonly lite?: boolean;
}

/**
 * A JSON Schema object, or a Standard JSON Schema value (zod 4, valibot,
 * arktype, ...) that can produce one.
 */
export type JsonSchemaSource =
  | Readonly<Record<string, unknown>>
  | {
      readonly "~standard": {
        readonly jsonSchema: {
          readonly input: (options: {
            readonly target: string;
          }) => Record<string, unknown>;
        };
      };
    };

export type JsonTypeConfig = (
  | { readonly import: string }
  | { readonly type: string }
) & {
  /** Enforced in the database by `better-supabase add jsonb-schemas` (pg_jsonschema). */
  readonly schema?: JsonSchemaSource;
};

export interface TableConfig {
  readonly casing?: Casing;
  /** Leave the table out of the generated models. */
  readonly exclude?: boolean;
  /**
   * Keep the table off the Data API on purpose: only `service_role` reaches
   * it. The models are still generated for admin clients, and doctor (BS106)
   * checks that `anon` and `authenticated` have no grants instead of
   * requiring them.
   */
  readonly serviceRole?: boolean;
  /** Rename generated relations: `{ primaryContact: 'contact' }`. */
  readonly relations?: Readonly<Record<string, string>>;
  /**
   * Database names of not-null columns an insert may leave out because the
   * database fills them, for example from a `before insert` trigger. `gen`
   * makes them optional in `InsertOf` and the insert validators.
   */
  readonly insertOptional?: readonly string[];
}

export interface FunctionConfig {
  /** `true`, or the `returns table` columns (database names) that are never null. */
  readonly notNull?: true | readonly string[];
}

export interface TimestampsConfig {
  readonly createdAt?: string;
  readonly updatedAt?: string;
}

export interface SoftDeleteConfig {
  readonly column?: string;
}

export interface TenantConfig {
  readonly column?: string;
}

/** Claim names shared by the SQL modules, codegen and the runtime defaults. */
export interface ClaimsConfig {
  /** Top-level claim holding the active tenant id. Defaults to `tenant_id`. */
  readonly tenant?: string;
  /** `scope` of the tenant entries `membership_claims()` writes. Defaults to `tenant`. */
  readonly scope?: string;
  /** Claim holding plan features per tenant (`{ [tenantId]: string[] }`). Defaults to `features`. */
  readonly features?: string;
  /** Claim the memberships hook (`membership_claims()` or the provider's) writes. Defaults to `memberships`. */
  readonly memberships?: string;
}

export interface ActorConfig {
  readonly createdBy?: string;
  readonly updatedBy?: string;
  /** Defaults to `impersonated_by`, the column the SQL modules' `track_actor` fills. */
  readonly impersonatedBy?: string;
}

export interface PluginFlagsConfig {
  readonly timestamps?: boolean | TimestampsConfig;
  readonly softDelete?: boolean | SoftDeleteConfig;
  readonly tenant?: boolean | TenantConfig;
  readonly actor?: boolean | ActorConfig;
}

/**
 * Runtime types for columns whose JSON form loses information. Defaults
 * match `supabase gen types`: timestamps as ISO strings, `int8` and
 * `numeric` as numbers.
 */
export interface CodecsConfig {
  /**
   * `'instant'` decodes `timestamptz` columns to `Temporal.Instant` and
   * `timestamp` columns to `Temporal.PlainDateTime`.
   */
  readonly timestamptz?: "string" | "instant";
  /** `'bigint'` or `'string'` read `int8` exactly (above 2^53). */
  readonly int8?: "number" | "string" | "bigint";
  /** `'string'` reads `numeric` exactly. */
  readonly numeric?: "number" | "string";
}

export interface GeneratedFile {
  /** Path relative to the project root. */
  readonly path: string;
  readonly contents: string;
}

export interface GeneratorInput {
  readonly meta: SchemaMeta;
  /**
   * The `@supabase/postgrest-typegen` metadata for the configured schemas,
   * the same contract `supabase gen types` is built on.
   */
  readonly introspection: GeneratorMetadata;
  /** Constraints, indexes, policies, triggers and grants typegen leaves out. */
  readonly extras: SnapshotExtras;
  readonly config: ResolvedConfig;
  /** Absolute path of the main generated module. */
  readonly output: string;
  /** Import path from `from` (a generated file) to `to`, with extension. */
  readonly importPath: (from: string, to: string) => string;
  /**
   * Where generated files import `better-supabase` runtime helpers from.
   * Defaults to `better-supabase`.
   */
  readonly runtimeImport?: string;
  /**
   * The tables and enums `gen` emits, with the TypeScript type it wrote for
   * each column (after `json` overrides, codecs and enum unions). Frozen.
   */
  readonly model: GeneratorModel;
}

export interface GeneratorColumn {
  /** Name in rows, after casing. */
  readonly app: string;
  /** Database name. */
  readonly db: string;
  /** TypeScript type without `| null`. */
  readonly tsType: string;
  readonly nullable: boolean;
  /** Optional on insert. */
  readonly optional: boolean;
  /** Generated or identity always: never written. */
  readonly readonly: boolean;
  /** Enum or check-constraint values, when the column has a closed set. */
  readonly values: readonly string[] | undefined;
  readonly json: boolean;
}

export interface GeneratorTable {
  /** Key in `schema.tables` and on the client. */
  readonly key: string;
  readonly schema: string;
  readonly name: string;
  readonly casing: Casing;
  readonly columns: readonly GeneratorColumn[];
}

export interface GeneratorModel {
  readonly tables: readonly GeneratorTable[];
  readonly enums: readonly {
    readonly schema: string;
    readonly name: string;
    readonly values: readonly string[];
  }[];
}

/**
 * Codegen extension point. First-party generators: `zod()`, `valibot()`,
 * `jsonSchema()`, `standardSchema()`. Prove custom ones with `testGenerator`.
 */
export interface Generator {
  /** The generator contract it targets. `gen` refuses versions it doesn't know. */
  readonly apiVersion?: 1;
  readonly name: string;
  generate(
    input: GeneratorInput,
  ): readonly GeneratedFile[] | Promise<readonly GeneratedFile[]>;
}

export interface RelationsConfig {
  /**
   * Type a to-one include as `| null` when the related table has row level
   * security, even over a `not null` foreign key, since a policy can hide
   * the related row. `required: true` on the include keeps it non-null.
   * Defaults to `false`.
   */
  readonly nullableUnderRls?: boolean;
}
