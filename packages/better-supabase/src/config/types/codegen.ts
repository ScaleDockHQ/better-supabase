import type { FieldSpec } from "../../core/table-json-schema.ts";
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
   * Read a Supabase Lite project's schema the way Lite runs it, from `[db]
   * driver` in `supabase/config.toml`. On by default when that key is present;
   * `false` reads the database like any other project.
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
  /**
   * Enforced in the database by `better-supabase add jsonb-schemas`
   * (pg_jsonschema).
   */
  readonly schema?: JsonSchemaSource;
};

export interface TableConfig {
  readonly casing?: Casing;
  /** Leave the table out of the generated models. */
  readonly exclude?: boolean;
  /**
   * Keep the table off the Data API on purpose: only `service_role` reaches it.
   * The models are still generated for admin clients, and doctor (BS106) checks
   * that `anon` and `authenticated` have no grants instead of requiring them.
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
  /**
   * `true`, or the `returns table` columns (database names) that are never
   * null.
   */
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
  /**
   * Defaults to `organization_id`, or `<blocks.tenant.names.organization>_id`
   * when the tenant is renamed.
   */
  readonly column?: string;
}

/** Claim names shared by the SQL modules, codegen and the runtime defaults. */
export interface ClaimsConfig {
  /** Top-level claim holding the active tenant id. Defaults to `tenant_id`. */
  readonly tenant?: string;
  /**
   * `scope` of the tenant entries `membership_claims()` writes. Defaults to
   * `tenant`.
   */
  readonly scope?: string;
  /**
   * Claim holding plan features per tenant (`{ [tenantId]: string[] }`).
   * Defaults to `features`.
   */
  readonly features?: string;
  /**
   * Claim the memberships hook (`membership_claims()` or the provider's)
   * writes. Defaults to `memberships`.
   */
  readonly memberships?: string;
}

export interface ActorConfig {
  readonly createdBy?: string;
  readonly updatedBy?: string;
  /**
   * Defaults to `impersonated_by`, the column the SQL modules' `track_actor`
   * fills.
   */
  readonly impersonatedBy?: string;
}

export interface PluginFlagsConfig {
  readonly timestamps?: boolean | TimestampsConfig;
  readonly softDelete?: boolean | SoftDeleteConfig;
  readonly tenant?: boolean | TenantConfig;
  readonly actor?: boolean | ActorConfig;
}

/**
 * Runtime types for columns whose JSON form loses information. Defaults match
 * `supabase gen types`: timestamps as ISO strings, `int8` and `numeric` as
 * numbers.
 */
export interface CodecsConfig {
  /**
   * `'instant'` decodes `timestamptz` columns to `Temporal.Instant` and
   * `timestamp` columns to `Temporal.PlainDateTime`. `'utc'` keeps
   * `timestamptz` columns as strings, always in UTC as ISO 8601 with a `Z` and
   * every fraction digit (`2026-10-21T05:10:00.123456Z`).
   */
  readonly timestamptz?: "string" | "instant" | "utc";
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
   * The `@supabase/postgrest-typegen` metadata for the configured schemas, the
   * same contract `supabase gen types` is built on.
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

export interface GeneratorFunctionArg {
  readonly name: string;
  /** TypeScript type, as `$rpc` takes it. */
  readonly tsType: string;
  /** Has a default, so callers may leave it out. */
  readonly optional: boolean;
  /** Enum values, when the argument is an enum (or an array of one). */
  readonly values: readonly string[] | undefined;
}

/** A function `$rpc` calls, with the types `gen` wrote for it. */
export interface GeneratorFunction {
  /** Name on `$rpc`. */
  readonly key: string;
  readonly schema: string;
  readonly args: readonly GeneratorFunctionArg[];
  /** TypeScript type of the result, as `$rpc` returns it. */
  readonly returns: string;
  readonly returnsSet: boolean;
  readonly volatility: "immutable" | "stable" | "volatile";
}

/** JSON Schema (draft 2020-12) for one value. */
export type GeneratorJsonSchema = Readonly<Record<string, unknown>>;

/**
 * One field of a block input schema: its scalar kind with the flags and bounds
 * `entitySchema` takes. It never carries a nested `schema`.
 */
export type GeneratorField = FieldSpec;

/** One of a block's input schemas, in the block's default names. */
export interface GeneratorInputSchema {
  /** The type it validates (`WorkItemInput`). */
  readonly title: string;
  readonly fields: Readonly<Record<string, GeneratorField>>;
  /** The same schema as JSON Schema (draft 2020-12), in its wire form. */
  readonly jsonSchema: GeneratorJsonSchema;
}

/**
 * The inputs a block's client takes for one entity. Each is absent when the
 * block declares none.
 */
export interface GeneratorEntitySchemas {
  /** What creating one takes (`WorkItemInput`). */
  readonly input?: GeneratorInputSchema;
  /** What updating one takes (`WorkItemChange`). */
  readonly change?: GeneratorInputSchema;
  /** What listing them takes (`WorkItemListOptions`). */
  readonly listFilter?: GeneratorInputSchema;
}

export interface GeneratorNoun {
  readonly singular: string;
  readonly plural: string;
}

/** One of an installed block's entities, under the name the config gives it. */
export interface GeneratorBlockEntity {
  /** The entity's key in the block's manifest: its default singular noun. */
  readonly key: string;
  /** The block's own noun (`work_item`). */
  readonly from: GeneratorNoun;
  /** The noun `blocks.<name>.names` gives it (`task`). */
  readonly to: GeneratorNoun;
  readonly primary: boolean;
  /** The table that holds it, as the SQL names it; undefined when none. */
  readonly table: string | undefined;
  /** `blocks.<name>.names.<entity>.url`, with column placeholders. */
  readonly url: string | undefined;
  readonly schemas: GeneratorEntitySchemas;
}

/** An installed block, with its final names. */
export interface GeneratorBlock {
  readonly name: string;
  /** The schema its tables and functions live in. */
  readonly schema: string;
  /**
   * The block's client in `blocks.generated.ts` (`tasksBlock`) and the subpath
   * its default export comes from, or undefined for blocks with only SQL.
   */
  readonly client:
    | { readonly export: string; readonly subpath: string }
    | undefined;
  readonly entities: readonly GeneratorBlockEntity[];
}

export interface GeneratorModel {
  readonly tables: readonly GeneratorTable[];
  readonly enums: readonly {
    readonly schema: string;
    readonly name: string;
    readonly values: readonly string[];
  }[];
  /** The functions `$rpc` calls, one entry per overload. */
  readonly functions: readonly GeneratorFunction[];
  /** The installed blocks, in config order. */
  readonly blocks: readonly GeneratorBlock[];
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
   * security, even over a `not null` foreign key, since a policy can hide the
   * related row. `required: true` on the include keeps it non-null. Defaults to
   * `false`.
   */
  readonly nullableUnderRls?: boolean;
}
