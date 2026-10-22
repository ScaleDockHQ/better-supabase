import type { PresetName } from "../../preset/presets.ts";
import type { Casing } from "../../schema/types.ts";
import type { AuthorizationProvider } from "../authorization.ts";
import type { BlocksConfig } from "../blocks.ts";
import type { ExposeConfig } from "../expose.ts";
import type { AppTableConfig } from "./app-tables.ts";
import type {
  ClaimsConfig,
  CodecsConfig,
  FunctionConfig,
  Generator,
  JsonTypeConfig,
  PluginFlagsConfig,
  RelationsConfig,
  SourceConfig,
  TableConfig,
} from "./codegen.ts";
import type {
  BucketConfig,
  RealtimeConfig,
  SeedConfig,
  SqlConfig,
  VectorSearchConfig,
} from "./database.ts";
import type { EntitlementsConfig } from "./entitlements.ts";
import type { SubjectsConfig } from "./subjects.ts";
import type {
  DoctorConfig,
  EnvFileConfig,
  GenConfig,
  IntegrationName,
  KeysConfig,
  OpenApiConfig,
  ScaffoldConfig,
  SkillsConfig,
  SpecsConfig,
} from "./tooling.ts";

interface LegacyBlockKeys {
  readonly mode?: unknown;
  readonly scope?: unknown;
  readonly entities?: unknown;
  readonly hooks?: unknown;
}

/**
 * One `blocks.<name>` entry as the config writes it: the block settings with
 * `ownership`, `owner`, `names` and `callbacks`.
 */
export type BlockInput<T extends LegacyBlockKeys> = Omit<
  T,
  keyof LegacyBlockKeys
> & {
  /**
   * Who owns the block's tables: `managed` (better-supabase writes them, the
   * default), `adopt` (your tables, mapped through `tables` and `columns`) or
   * `custom` (your functions behind the block's contract).
   */
  readonly ownership?: T["mode"];
  /**
   * Who the block's rows belong to. Defaults to `database.sql.owner`, then
   * `tenant`.
   */
  readonly owner?: T["scope"];
  /** New names for the block's entities. */
  readonly names?: T["entities"];
  /**
   * The app's optional `before_*` and `after_*` functions the block calls when
   * they exist, e.g. `after_organization_create(organization, user)`.
   */
  readonly callbacks?: T["hooks"];
};

/** `blocks` keyed by block name, as the config writes it. */
export type BlocksInput = {
  readonly [M in keyof BlocksConfig]?: BlockInput<NonNullable<BlocksConfig[M]>>;
};

/** One `tables.<name>` entry: an app table with `owner`. */
export type AppTableInput = Omit<AppTableConfig, "scope"> & {
  /**
   * Who reaches a row. `inherit` (the default) follows `database.sql.owner`;
   * `user` keeps rows per user, and `none` lets signed-in users read every row
   * while only the service role writes.
   */
  readonly owner?: AppTableConfig["scope"];
};

export type AppTablesInput = Readonly<Record<string, AppTableInput>>;

/** `database.sql`: SQL-wide settings with `owner`. */
export type SqlInput = Omit<SqlConfig, "scope"> & {
  /**
   * Who a block's rows belong to, unless `blocks.<name>.owner` sets its own:
   * `tenant` (the default), `user` or `none`.
   */
  readonly owner?: SqlConfig["scope"];
};

/** Where the active organization of a request comes from. */
export interface OrganizationConfig {
  /**
   * Top-level claim holding the active organization id. Defaults to
   * `tenant_id`.
   */
  readonly claim?: string;
  /**
   * The column holding the organization id on tenant tables, for the `tenant`
   * plugin flag. Defaults to `organization_id`, or `<name>_id` when
   * `blocks.tenant.names.organization` renames it.
   */
  readonly column?: string;
}

/** The database: where it is read from, its SQL and what it exposes. */
export interface DatabaseConfig {
  readonly source?: SourceConfig;
  /** Postgres schemas to generate. Defaults to `['public']`. */
  readonly schemas?: readonly string[];
  /**
   * SQL-wide settings: the workflow, paths, and the `schema`, `api` and `owner`
   * every block inherits.
   */
  readonly sql?: SqlInput;
  readonly seed?: SeedConfig;
  /**
   * Data API grants, keyed by `table` or `schema.table`, and function `execute`
   * grants, keyed by `name(argument types)` or `schema.name(argument types)`.
   */
  readonly expose?: Readonly<Record<string, ExposeConfig>>;
  readonly buckets?: Readonly<Record<string, BucketConfig>>;
  readonly realtime?: RealtimeConfig;
  /**
   * Realtime topic templates: `{ notifications:
   * 'organization:{organizationId}:notifications' }`.
   */
  readonly topics?: Readonly<Record<string, string>>;
  /**
   * Embedding columns, keyed by `table` or `schema.table`. The `vector-search`
   * block writes `search_<table>(query, k)` for each.
   */
  readonly vectorSearch?: Readonly<Record<string, VectorSearchConfig>>;
}

/** Who the caller is: the organization, claims and authorization. */
export interface AuthConfig {
  readonly organization?: OrganizationConfig;
  /** Claim names shared by the SQL, codegen and the runtime. */
  readonly claims?: Omit<ClaimsConfig, "tenant">;
  /**
   * An authorization system the blocks, policies and doctor delegate to: the
   * `provider` access model, `entitlements.memberships` and the hook and policy
   * checks.
   */
  readonly authorization?: AuthorizationProvider;
  readonly entitlements?: EntitlementsConfig;
}

/** What `better-supabase gen` writes and how. */
export interface GenGroupConfig extends GenConfig {
  /**
   * Main generated module. Defaults to `src/lib/supabase/generated.ts`;
   * `database.types.ts` is written next to it.
   */
  readonly output?: string;
  /** Casing of generated models and returned rows. Defaults to `'snake'`. */
  readonly casing?: Casing;
  /**
   * PostgREST major version, written to `__InternalSupabase` in
   * `database.types.ts`. Defaults to `'13'`.
   */
  readonly postgrestVersion?: string;
  /**
   * Write one record feature per record type into `features/` next to `output`.
   * Defaults to `true`.
   */
  readonly generateFeatures?: boolean;
  /** Overrides per generated table, keyed by `table` or `schema.table`. */
  readonly tables?: Readonly<Record<string, TableConfig>>;
  /** Types for jsonb columns, keyed by `table.column`. */
  readonly json?: Readonly<Record<string, JsonTypeConfig>>;
  readonly codecs?: CodecsConfig;
  readonly relations?: RelationsConfig;
  /**
   * Columns that must not be read by accident (`table.column` or
   * `schema.table.column`, database names), for the `noSensitiveSelect` rule.
   */
  readonly sensitive?: readonly string[];
  /**
   * Text columns that hold an object path, keyed by `table.column` or
   * `schema.table.column`, with the bucket as the value (a `database.buckets`
   * key or a bucket id).
   */
  readonly storagePaths?: Readonly<Record<string, string>>;
  /** Function results `gen` may type as not null, keyed by function name. */
  readonly functions?: Readonly<Record<string, FunctionConfig>>;
  readonly generators?: readonly Generator[];
  /**
   * Modules that export `defineReadSet` results, compiled to functions in the
   * `read-sets` block.
   */
  readonly readSets?: readonly string[];
}

/** The API documents `better-supabase spec emit` writes. */
export interface ApiConfig {
  /** @deprecated Use `specs`; `openapi.entry` and `openapi.output` map onto it. */
  readonly openapi?: OpenApiConfig;
  /** The documents `spec emit` writes (OpenAPI, AsyncAPI, Arazzo). */
  readonly specs?: SpecsConfig;
}

/** Project tooling: doctor, env files, keys, skills and scaffolds. */
export interface ToolingConfig {
  readonly doctor?: DoctorConfig;
  readonly env?: EnvFileConfig;
  readonly keys?: KeysConfig;
  readonly skills?: SkillsConfig;
  readonly scaffold?: ScaffoldConfig;
}

/** The plugin flags; the tenant column is `auth.organization.column`. */
export type PluginFlagsInput = Omit<PluginFlagsConfig, "tenant"> & {
  readonly tenant?: boolean;
};

/** `better-supabase.config.ts`, grouped by what each key configures. */
export interface BetterSupabaseConfig {
  readonly $schema?: string;
  /**
   * A named preset (`saas`, `crm`, ...), a code from `/create`, or its URL. It
   * expands into `blocks` and the conventions it sets; the keys you set win.
   */
  readonly preset?: PresetName | (string & {});
  readonly database?: DatabaseConfig;
  readonly auth?: AuthConfig;
  /**
   * The app's record types: the entities blocks attach tags, comments, fields
   * and ranks to, keyed by type name.
   */
  readonly records?: SubjectsConfig;
  /**
   * Tables the app owns, keyed by name, created in `public` by `better-supabase
   * sql sync`. ADR 0040.
   */
  readonly tables?: AppTablesInput;
  /**
   * The blocks to install and keep in sync: a list of names, or an object keyed
   * by block name whose values set each block's ownership, names and options.
   */
  readonly blocks?: readonly string[] | BlocksInput;
  /** The framework and runtime adapters `init` and `add` wrote. */
  readonly adapters?: readonly IntegrationName[];
  /** Enables plugin flags in the generated metadata. */
  readonly plugins?: PluginFlagsInput;
  readonly gen?: GenGroupConfig;
  readonly api?: ApiConfig;
  readonly tooling?: ToolingConfig;
  /**
   * Overrides per environment, keyed by name. The CLI applies the block for
   * `--env <name>`, else `$BETTER_SUPABASE_ENV`, else `ci` when `$CI` is set.
   * Objects merge into the config; arrays and other values replace.
   */
  readonly $env?: Readonly<Record<string, EnvironmentConfig>>;
  /** Shorthand for `$env.development`. */
  readonly $development?: EnvironmentConfig;
  /** Shorthand for `$env.production`. */
  readonly $production?: EnvironmentConfig;
  /** Shorthand for `$env.test`. */
  readonly $test?: EnvironmentConfig;
  /** Shorthand for `$env.ci`, which the CLI picks when `$CI` is set. */
  readonly $ci?: EnvironmentConfig;
}

/** The keys an environment block may override. */
export type EnvironmentConfig = Omit<
  BetterSupabaseConfig,
  | "$schema"
  | "$env"
  | "$development"
  | "$production"
  | "$test"
  | "$ci"
  | "preset"
>;
