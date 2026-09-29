import type { GeneratorMetadata } from '../cli/introspect/typegen.ts';
import type { SnapshotExtras } from '../cli/introspect/types.ts';
import type { Casing, SchemaMeta } from '../schema/types.ts';

export {
  buildJsonSchema,
  jsonSchema,
  type JsonSchemaGeneratorOptions,
} from '../generators/json-schema.ts';
export {
  valibot,
  type ValibotGeneratorOptions,
} from '../generators/valibot.ts';
export { zod, type ZodGeneratorOptions } from '../generators/zod.ts';

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
      readonly '~standard': {
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
  const standard = (source as { '~standard'?: unknown })['~standard'];
  if (standard === undefined)
    return source as Readonly<Record<string, unknown>>;
  const jsonSchema = (standard as { jsonSchema?: unknown }).jsonSchema as
    | { input?: (options: { target: string }) => Record<string, unknown> }
    | undefined;
  if (typeof jsonSchema?.input !== 'function') {
    throw new TypeError(
      'json[...].schema: this Standard Schema library does not implement Standard JSON Schema; pass a JSON Schema object instead',
    );
  }
  return jsonSchema.input({ target: 'draft-2020-12' });
}

export interface TableConfig {
  readonly casing?: Casing;
  /** Leave the table out of the generated models. */
  readonly exclude?: boolean;
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
  /** JWT claim holding the tenant id. */
  readonly claim?: string;
}

export interface ActorConfig {
  readonly createdBy?: string;
  readonly updatedBy?: string;
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
  /** Generated storage policy. */
  readonly policy?: 'tenant' | 'owner' | 'public' | 'none';
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
}

/**
 * Runtime types for columns whose JSON form loses information. Defaults
 * match `supabase gen types`: timestamps as ISO strings, `int8` and
 * `numeric` as numbers.
 */
export interface CodecsConfig {
  /** `'date'` decodes `timestamptz`/`timestamp` columns to `Date`. */
  readonly timestamptz?: 'string' | 'date';
  /** `'bigint'` or `'string'` read `int8` exactly (above 2^53). */
  readonly int8?: 'number' | 'string' | 'bigint';
  /** `'string'` reads `numeric` exactly. */
  readonly numeric?: 'number' | 'string';
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
}

/**
 * Codegen extension point. First-party generators: `zod()`, `valibot()`,
 * `jsonSchema()`. Prove custom ones with `testGenerator`.
 */
export interface Generator {
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
}

/** A privilege the Data API roles can be granted on a table or view. */
export type Privilege = 'select' | 'insert' | 'update' | 'delete';

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
   * Data API grants, keyed by `table` or `schema.table`. Supabase no longer
   * grants new tables to `anon` and `authenticated` automatically; the
   * `grants` SQL kit module writes these, and doctor (BS106) checks them.
   * Tables not listed need `select, insert, update, delete` for
   * `authenticated` (`select` for views).
   */
  readonly expose?: Readonly<Record<string, ExposeConfig>>;
  readonly generators?: readonly Generator[];
  /** Enables plugin flags in the generated metadata. */
  readonly plugins?: PluginFlagsConfig;
  readonly buckets?: Readonly<Record<string, BucketConfig>>;
  /** Realtime topic templates: `{ notifications: 'org:{orgId}:notifications' }`. */
  readonly topics?: Readonly<Record<string, string>>;
  readonly realtime?: RealtimeConfig;
  readonly sql?: SqlConfig;
  readonly seed?: SeedConfig;
  readonly openapi?: OpenApiConfig;
  readonly doctor?: DoctorConfig;
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
  readonly expose: Readonly<Record<string, ResolvedExpose>>;
  readonly generators: readonly Generator[];
  readonly plugins: {
    readonly timestamps: Required<TimestampsConfig> | undefined;
    readonly softDelete: Required<SoftDeleteConfig> | undefined;
    readonly tenant: Required<TenantConfig> | undefined;
    readonly actor: Required<ActorConfig> | undefined;
  };
  readonly buckets: Readonly<Record<string, BucketConfig>>;
  readonly topics: Readonly<Record<string, string>>;
  readonly realtime: Required<RealtimeConfig>;
  readonly sql: Required<SqlConfig>;
  readonly seed: Required<SeedConfig>;
  readonly openapi: Required<OpenApiConfig>;
  readonly doctor: Required<DoctorConfig>;
}

export const CONFIG_SCHEMA_URL =
  'https://unpkg.com/better-supabase/schemas/config-v1.json';

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
  return { ...defaults, ...value } as Required<T>;
}

function resolveExpose(entry: ExposeConfig): ResolvedExpose {
  if (Array.isArray(entry)) return { anon: [], authenticated: entry };
  const roles = entry as Exclude<ExposeConfig, readonly Privilege[]>;
  return { anon: roles.anon ?? [], authenticated: roles.authenticated ?? [] };
}

/** Applies defaults. Paths stay relative to `root`. */
export function resolveConfig(
  config: BetterSupabaseConfig,
  root: string,
): ResolvedConfig {
  const output = config.output ?? 'src/lib/supabase/generated.ts';
  return {
    root,
    source: config.source ?? {},
    schemas: config.schemas ?? ['public'],
    casing: config.casing ?? 'snake',
    tables: config.tables ?? {},
    output,
    databaseTypesOutput: output.replace(/[^/]+$/, 'database.types.ts'),
    postgrestVersion: config.postgrestVersion ?? '13',
    json: config.json ?? {},
    codecs: {
      timestamptz: config.codecs?.timestamptz ?? 'string',
      int8: config.codecs?.int8 ?? 'number',
      numeric: config.codecs?.numeric ?? 'number',
    },
    sensitive: config.sensitive ?? [],
    expose: Object.fromEntries(
      Object.entries(config.expose ?? {}).map(([table, entry]) => [
        table,
        resolveExpose(entry),
      ]),
    ),
    generators: config.generators ?? [],
    plugins: {
      timestamps: pick(config.plugins?.timestamps, {
        createdAt: 'created_at',
        updatedAt: 'updated_at',
      }),
      softDelete: pick(config.plugins?.softDelete, { column: 'deleted_at' }),
      tenant: pick(config.plugins?.tenant, {
        column: 'organization_id',
        claim: 'org_id',
      }),
      actor: pick(config.plugins?.actor, {
        createdBy: 'created_by',
        updatedBy: 'updated_by',
      }),
    },
    buckets: config.buckets ?? {},
    topics: config.topics ?? {},
    realtime: { tables: config.realtime?.tables ?? [] },
    sql: {
      dir: config.sql?.dir ?? 'supabase/schemas',
      prefix: config.sql?.prefix ?? '900_better_supabase',
      testsDir: config.sql?.testsDir ?? 'supabase/tests',
      kit: config.sql?.kit ?? [],
    },
    seed: {
      entry: config.seed?.entry ?? 'supabase/seed.ts',
      output: config.seed?.output ?? 'supabase/seeds/000_better_supabase.sql',
    },
    openapi: {
      entry: config.openapi?.entry ?? 'src/lib/openapi.ts',
      output: config.openapi?.output ?? 'openapi.json',
    },
    doctor: {
      ignore: config.doctor?.ignore ?? [],
      strict: config.doctor?.strict ?? false,
    },
  };
}
