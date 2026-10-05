import type {
  AccessBucketPolicy,
  BucketPolicyName,
  Casing,
  PermdockBucketPolicy,
  SchemaMeta,
} from "../schema/types.ts";
import type { KitsConfig } from "./kits.ts";
import type { GeneratorMetadata, SnapshotExtras } from "./snapshot.ts";

import { DEFAULT_CLAIMS } from "../core/claims.ts";

export type { Casing };

/**
 * Where codegen reads the database from. Without any of these, `$DATABASE_URL`
 * and then the local stack (`supabase start`) are used.
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
  /** Enforced in the database by `sql add jsonb-schemas` (pg_jsonschema). */
  readonly schema?: JsonSchemaSource;
};

/** The JSON Schema document for a `json[...].schema` entry. */
export function resolveJsonSchema(
  source: JsonSchemaSource,
): Readonly<Record<string, unknown>> {
  // SAFETY: a Standard Schema carries ~standard; any other source is a JSON
  // Schema object without it.
  const standard = (source as { "~standard"?: unknown })["~standard"];
  if (standard === undefined) return source;
  // SAFETY: Standard JSON Schema puts jsonSchema.input on ~standard; its
  // absence is handled below.
  const jsonSchema = (standard as { jsonSchema?: unknown }).jsonSchema as
    | { input?: (options: { target: string }) => Record<string, unknown> }
    | undefined;
  if (typeof jsonSchema?.input !== "function") {
    throw new TypeError(
      "json[...].schema: this Standard Schema library does not implement Standard JSON Schema; pass a JSON Schema object instead",
    );
  }
  return jsonSchema.input({ target: "draft-2020-12" });
}

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

/**
 * Claim names shared by the SQL kit, codegen and the runtime defaults. They
 * follow PermDock's claim contract.
 */
export interface ClaimsConfig {
  /** Top-level claim holding the active tenant id. Defaults to `tenant_id`. */
  readonly tenant?: string;
  /** `scope` of the tenant entries `membership_claims()` writes. Defaults to `tenant`. */
  readonly scope?: string;
  /** Claim holding plan features per tenant (`{ [tenantId]: string[] }`). Defaults to `features`. */
  readonly features?: string;
}

export interface ActorConfig {
  readonly createdBy?: string;
  readonly updatedBy?: string;
  /** Defaults to `impersonated_by`, the column the SQL kit's `track_actor` fills. */
  readonly impersonatedBy?: string;
}

export interface PluginFlagsConfig {
  readonly timestamps?: boolean | TimestampsConfig;
  readonly softDelete?: boolean | SoftDeleteConfig;
  readonly tenant?: boolean | TenantConfig;
  readonly actor?: boolean | ActorConfig;
}

export interface BucketConfig {
  readonly id?: string;
  readonly public?: boolean;
  /** Path template with `{placeholders}`, e.g. `{orgId}/{customerId}/logo.webp`. */
  readonly path: string;
  /**
   * Generated storage policy, a PermDock policy (`{ permdock, scope }`) or
   * an access contract policy (`{ access }`).
   */
  readonly policy?:
    | BucketPolicyName
    | PermdockBucketPolicy
    | AccessBucketPolicy;
  readonly fileSizeLimit?: string;
  readonly allowedMimeTypes?: readonly string[];
}

export interface SqlConfig {
  /** Directory declarative schema files are written to. */
  readonly dir?: string;
  /** File name prefix, so generated files sort after yours. */
  readonly prefix?: string;
  /** Directory pgTAP files (the `pgtap` module) are written to. */
  readonly testsDir?: string;
  /** SQL kit modules to keep in sync (`better-supabase sql add`). */
  readonly kit?: readonly string[];
}

export interface SeedConfig {
  /** Module exporting `defineSeed(...)` as `seed` or default. */
  readonly entry?: string;
  /** SQL file `better-supabase seed` writes. Add it to `[db.seed] sql_paths`. */
  readonly output?: string;
}

export interface OpenApiConfig {
  /** Module exporting the document (or a function returning it) as `openapi` or default. */
  readonly entry?: string;
  /** JSON file `better-supabase openapi emit` writes. */
  readonly output?: string;
}

export interface DoctorConfig {
  /** Finding codes to skip, e.g. `['BS204']`. */
  readonly ignore?: readonly string[];
  /** Treat warnings as errors. */
  readonly strict?: boolean;
  /**
   * App source files doctor scans for API use (BS210). Globs relative to the
   * root. Defaults to `['src/**\/*.{ts,tsx}']`.
   */
  readonly sources?: readonly string[];
  /**
   * How many policies a security definer helper may appear in before BS206
   * asks for an inlinable `language sql stable` function. Defaults to 5.
   */
  readonly policyHelperLimit?: number;
  /**
   * The BS405 limit in bytes. With a `permdock.config.ts` it is PermDock's
   * budget for `memberships` plus `attrs` (default 1024, matching
   * `supabase.hook.budget`) and the whole token keeps 2048. Without one it
   * limits the whole token's claims (default 2048).
   */
  readonly claimsLimit?: number;
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
 * `jsonSchema()`. Prove custom ones with `testGenerator`.
 */
export interface Generator {
  /** The generator contract it targets. `gen` refuses versions it doesn't know. */
  readonly apiVersion?: 1;
  readonly name: string;
  generate(
    input: GeneratorInput,
  ): readonly GeneratedFile[] | Promise<readonly GeneratedFile[]>;
}

export interface RealtimeConfig {
  /**
   * Tables that broadcast a change signal for live queries (`table` or
   * `schema.table`). Tenant tables broadcast per tenant. Install the
   * triggers with `better-supabase sql add realtime-tables`.
   */
  readonly tables?: readonly string[];
  /**
   * Tables in `tables` without a tenant column. They broadcast on one topic
   * every signed-in user receives. With the `tenant` plugin, a table that
   * lacks the tenant column and is not listed here fails to install.
   */
  readonly global?: readonly string[];
}

export interface EntitlementsConfig {
  /**
   * `table.column` (or `schema.table.column`) holding each tenant's Stripe
   * customer id, read by the `entitlements` SQL kit module. Required
   * without the `organizations` module; with it, defaults to the
   * `stripe_customer_id` column that module adds.
   */
  readonly customer?: string;
  /** The tenant id column of that table. Defaults to `id`. */
  readonly key?: string;
  /**
   * With a PermDock manifest, `has_entitlement` and `feature_claims` read
   * PermDock's memberships (`member_<scope>_ids()` and
   * `member_<scope>_ids_for(user)`) instead of `better_supabase.memberships`.
   * `scope` is the PermDock scope tenants are. It defaults to the manifest's
   * root scope (the `rls.scopes` entry without `within`); `false` keeps the
   * kit's memberships table.
   */
  readonly permdock?: false | { readonly scope?: string };
}

export interface PermdockPathsConfig {
  /** What `permdock supabase inspect --out` writes. Defaults to `permdock.manifest.json`. */
  readonly manifest?: string;
  /** What `permdock catalog` writes. Defaults to `permissions.catalog.json`. */
  readonly catalog?: string;
}

/** pgvector distance: `<=>` (cosine), `<->` (l2) or `<#>` (negative inner product). */
export type VectorDistance = "cosine" | "l2" | "inner_product";

/** The embedding column, or the column and its distance (default `cosine`). */
export type VectorSearchConfig =
  | string
  | { readonly column: string; readonly distance?: VectorDistance };

/** A privilege the Data API roles can be granted on a table or view. */
export type Privilege = "select" | "insert" | "update" | "delete";

/**
 * Data API grants for one table: privileges for `authenticated`, or per
 * role.
 */
export type ExposeConfig =
  | readonly Privilege[]
  | {
      readonly anon?: readonly Privilege[];
      readonly authenticated?: readonly Privilege[];
    };

/** Resolved grants for one table. */
export interface ResolvedExpose {
  readonly anon: readonly Privilege[];
  readonly authenticated: readonly Privilege[];
}

export interface BetterSupabaseConfig {
  readonly $schema?: string;
  readonly source?: SourceConfig;
  /** Postgres schemas to generate. Defaults to `['public']`. */
  readonly schemas?: readonly string[];
  /** Casing of generated models and returned rows. Defaults to `'snake'`. */
  readonly casing?: Casing;
  readonly tables?: Readonly<Record<string, TableConfig>>;
  /**
   * Main generated module. Defaults to `src/lib/supabase/generated.ts`;
   * `database.types.ts` is written next to it.
   */
  readonly output?: string;
  /**
   * PostgREST major version, written to `__InternalSupabase` in
   * `database.types.ts` so `createClient` picks matching behavior.
   * Defaults to `'13'`.
   */
  readonly postgrestVersion?: string;
  /** Types for jsonb columns, keyed by `table.column`. */
  readonly json?: Readonly<Record<string, JsonTypeConfig>>;
  readonly codecs?: CodecsConfig;
  /**
   * Columns that must not be read by accident (`table.column` or
   * `schema.table.column`, database names), for the `noSensitiveSelect` rule.
   */
  readonly sensitive?: readonly string[];
  /**
   * Text columns that hold an object path, keyed by `table.column` or
   * `schema.table.column` (database names), with the bucket as the value (a
   * `buckets` key or a bucket id). Generated rows type them as
   * `StoragePath<'bucket-id'>`.
   */
  readonly storagePaths?: Readonly<Record<string, string>>;
  /**
   * Data API grants, keyed by `table` or `schema.table`. Supabase no longer
   * grants new tables to `anon` and `authenticated` automatically; the
   * `grants` SQL kit module writes these, and doctor (BS106) checks them.
   * Tables not listed need `select, insert, update, delete` for
   * `authenticated` (`select` for views).
   */
  readonly expose?: Readonly<Record<string, ExposeConfig>>;
  /**
   * Modules that export `defineReadSet` results. `gen` compiles each set to
   * a function in the `read-sets` SQL kit module. Node imports them, so
   * relative imports need their `.ts` extension.
   */
  readonly readSets?: readonly string[];
  readonly generators?: readonly Generator[];
  /** Enables plugin flags in the generated metadata. */
  readonly plugins?: PluginFlagsConfig;
  readonly claims?: ClaimsConfig;
  readonly buckets?: Readonly<Record<string, BucketConfig>>;
  /** Realtime topic templates: `{ notifications: 'org:{orgId}:notifications' }`. */
  readonly topics?: Readonly<Record<string, string>>;
  readonly realtime?: RealtimeConfig;
  readonly entitlements?: EntitlementsConfig;
  /** Where PermDock's JSON outputs are, for doctor, `gen` and the SQL kit. */
  readonly permdock?: PermdockPathsConfig;
  /**
   * Embedding columns, keyed by `table` or `schema.table`. The
   * `vector-search` SQL kit module writes `search_<table>(query, k)` for each,
   * which `db.$search(table, { vector, k })` calls.
   */
  readonly vectorSearch?: Readonly<Record<string, VectorSearchConfig>>;
  readonly sql?: SqlConfig;
  /**
   * How each SQL kit module maps onto the database: `managed` tables, or
   * `adopt` and `custom` over the app's own, with table, column and
   * permission names, keyed by module name.
   */
  readonly kits?: KitsConfig;
  readonly seed?: SeedConfig;
  readonly openapi?: OpenApiConfig;
  readonly doctor?: DoctorConfig;
}

function entitlementsOf(
  config: EntitlementsConfig = {},
): ResolvedConfig["entitlements"] {
  const customer = config.customer;
  const dot = customer?.lastIndexOf(".") ?? -1;
  if (customer !== undefined && dot <= 0) {
    throw new TypeError(
      `entitlements.customer must be "table.column", got "${customer}"`,
    );
  }
  return {
    ...(customer === undefined
      ? {}
      : { table: customer.slice(0, dot), column: customer.slice(dot + 1) }),
    key: config.key ?? "id",
    permdock:
      config.permdock === false
        ? false
        : config.permdock?.scope === undefined
          ? {}
          : { scope: config.permdock.scope },
  };
}

function vectorSearchOf(
  config: Readonly<Record<string, VectorSearchConfig>> = {},
): ResolvedConfig["vectorSearch"] {
  return Object.entries(config).map(([table, entry]) =>
    typeof entry === "string"
      ? { table, column: entry, distance: "cosine" }
      : { table, column: entry.column, distance: entry.distance ?? "cosine" },
  );
}

/** The config with defaults applied. */
export interface ResolvedConfig {
  readonly root: string;
  readonly source: SourceConfig;
  readonly schemas: readonly string[];
  readonly casing: Casing;
  readonly tables: Readonly<Record<string, TableConfig>>;
  readonly output: string;
  /** `database.types.ts` next to `output`. */
  readonly databaseTypesOutput: string;
  readonly postgrestVersion: string;
  readonly json: Readonly<Record<string, JsonTypeConfig>>;
  readonly codecs: Required<CodecsConfig>;
  readonly sensitive: readonly string[];
  readonly storagePaths: Readonly<Record<string, string>>;
  readonly expose: Readonly<Record<string, ResolvedExpose>>;
  readonly readSets: readonly string[];
  readonly generators: readonly Generator[];
  readonly plugins: {
    readonly timestamps: Required<TimestampsConfig> | undefined;
    readonly softDelete: Required<SoftDeleteConfig> | undefined;
    readonly tenant: Required<TenantConfig> | undefined;
    readonly actor: Required<ActorConfig> | undefined;
  };
  readonly claims: Required<ClaimsConfig>;
  readonly buckets: Readonly<Record<string, BucketConfig>>;
  readonly entitlements: {
    /** Unset without `entitlements.customer`. */
    readonly table?: string;
    readonly column?: string;
    readonly key: string;
    readonly permdock: false | { readonly scope?: string };
  };
  readonly permdock: Required<PermdockPathsConfig>;
  readonly vectorSearch: readonly {
    readonly table: string;
    readonly column: string;
    readonly distance: VectorDistance;
  }[];
  readonly topics: Readonly<Record<string, string>>;
  readonly realtime: Required<RealtimeConfig>;
  readonly sql: Required<SqlConfig>;
  readonly kits: KitsConfig;
  readonly seed: Required<SeedConfig>;
  readonly openapi: Required<OpenApiConfig>;
  readonly doctor: Required<Omit<DoctorConfig, "claimsLimit">> &
    Pick<DoctorConfig, "claimsLimit">;
}

export const CONFIG_SCHEMA_URL =
  "https://unpkg.com/better-supabase/schemas/config-v1.json";

/** Identity helper that types `better-supabase.config.ts`. */
export function defineConfig(
  config: BetterSupabaseConfig,
): BetterSupabaseConfig {
  return config;
}

function pick<T extends object>(
  value: boolean | T | undefined,
  defaults: Required<T>,
): Required<T> | undefined {
  if (value === undefined || value === false) return undefined;
  if (value === true) return defaults;
  return { ...defaults, ...value };
}

function resolveExpose(entry: ExposeConfig): ResolvedExpose {
  if (Array.isArray(entry)) return { anon: [], authenticated: entry };
  // SAFETY: the Array.isArray check above removed the privilege-list form.
  const roles = entry as Exclude<ExposeConfig, readonly Privilege[]>;
  return { anon: roles.anon ?? [], authenticated: roles.authenticated ?? [] };
}

function generatorsOf(
  generators: readonly Generator[] | undefined,
): readonly Generator[] {
  for (const generator of generators ?? []) {
    const version: unknown = generator.apiVersion;
    if (version !== undefined && version !== 1) {
      throw new TypeError(
        `generator "${generator.name}" targets generator API ${String(version)}; this better-supabase supports 1. Upgrade better-supabase or use a release of the generator for API 1.`,
      );
    }
  }
  return generators ?? [];
}

/** Applies defaults. Paths stay relative to `root`. */
export function resolveConfig(
  config: BetterSupabaseConfig,
  root: string,
): ResolvedConfig {
  const output = config.output ?? "src/lib/supabase/generated.ts";
  return {
    root,
    source: config.source ?? {},
    schemas: config.schemas ?? ["public"],
    casing: config.casing ?? "snake",
    tables: config.tables ?? {},
    output,
    databaseTypesOutput: output.replace(/[^/]+$/, "database.types.ts"),
    postgrestVersion: config.postgrestVersion ?? "13",
    json: config.json ?? {},
    codecs: {
      timestamptz: config.codecs?.timestamptz ?? "string",
      int8: config.codecs?.int8 ?? "number",
      numeric: config.codecs?.numeric ?? "number",
    },
    sensitive: config.sensitive ?? [],
    storagePaths: config.storagePaths ?? {},
    expose: Object.fromEntries(
      Object.entries(config.expose ?? {}).map(([table, entry]) => [
        table,
        resolveExpose(entry),
      ]),
    ),
    readSets: config.readSets ?? [],
    generators: generatorsOf(config.generators),
    plugins: {
      timestamps: pick(config.plugins?.timestamps, {
        createdAt: "created_at",
        updatedAt: "updated_at",
      }),
      softDelete: pick(config.plugins?.softDelete, { column: "deleted_at" }),
      tenant: pick(config.plugins?.tenant, { column: "organization_id" }),
      actor: pick(config.plugins?.actor, {
        createdBy: "created_by",
        updatedBy: "updated_by",
        impersonatedBy: "impersonated_by",
      }),
    },
    claims: { ...DEFAULT_CLAIMS, ...config.claims },
    buckets: config.buckets ?? {},
    topics: config.topics ?? {},
    realtime: {
      tables: config.realtime?.tables ?? [],
      global: config.realtime?.global ?? [],
    },
    entitlements: entitlementsOf(config.entitlements),
    permdock: {
      manifest: config.permdock?.manifest ?? "permdock.manifest.json",
      catalog: config.permdock?.catalog ?? "permissions.catalog.json",
    },
    vectorSearch: vectorSearchOf(config.vectorSearch),
    sql: {
      dir: config.sql?.dir ?? "supabase/schemas",
      prefix: config.sql?.prefix ?? "900_better_supabase",
      testsDir: config.sql?.testsDir ?? "supabase/tests",
      kit: config.sql?.kit ?? [],
    },
    kits: config.kits ?? {},
    seed: {
      entry: config.seed?.entry ?? "supabase/seed.ts",
      output: config.seed?.output ?? "supabase/seeds/000_better_supabase.sql",
    },
    openapi: {
      entry: config.openapi?.entry ?? "src/lib/openapi.ts",
      output: config.openapi?.output ?? "openapi.json",
    },
    doctor: {
      ignore: config.doctor?.ignore ?? [],
      strict: config.doctor?.strict ?? false,
      sources: config.doctor?.sources ?? ["src/**/*.{ts,tsx}"],
      policyHelperLimit: config.doctor?.policyHelperLimit ?? 5,
      ...(config.doctor?.claimsLimit === undefined
        ? {}
        : { claimsLimit: config.doctor.claimsLimit }),
    },
  };
}
