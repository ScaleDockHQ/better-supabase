import type { PresetName } from "../../preset/presets.ts";
import type { PresetSpec } from "../../preset/spec.ts";
import type { Casing } from "../../schema/types.ts";
import type { AuthorizationProvider } from ".././authorization.ts";
import type { AnyBlocksConfig, BlocksConfig } from "../blocks.ts";
import type { ExposeConfig, ExposeRole, ResolvedExpose } from "../expose.ts";
import type { ResolvedInstance } from "../instances.ts";
import type { AppTablesConfig } from "./app-tables.ts";
import type {
  ClaimsConfig,
  CodecsConfig,
  FunctionConfig,
  Generator,
  JsonTypeConfig,
  RelationsConfig,
  SourceConfig,
  TableConfig,
} from "./codegen.ts";
import type {
  BucketConfig,
  RealtimeConfig,
  ResolvedSqlConfig,
  SeedConfig,
  SqlConfig,
  TopicPoliciesConfig,
  VectorDistance,
  VectorSearchConfig,
} from "./database.ts";
import type { EntitlementsConfig } from "./entitlements.ts";
import type { OrganizationConfig } from "./groups.ts";
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
  SpecOutputConfig,
  SpecsConfig,
} from "./tooling.ts";

/** The frameworks `gen.hooks` writes data hooks for. */
export type DataHooksFramework = "react" | "vue" | "svelte" | "solid";

/**
 * The config with every key at the top level, as `flattenConfig` returns it and
 * `resolveConfig` reads it. Apps write the grouped `BetterSupabaseConfig`.
 */
export interface FlatConfig {
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
   * `database.types.ts` so `createClient` picks matching behavior. Defaults to
   * `'13'`.
   */
  readonly postgrestVersion?: string;
  /**
   * Write one `records/<type>.ts` next to `output` per record type that an
   * installed block binds to (`defineRecordType`). Defaults to `true`.
   */
  readonly recordTypes?: boolean;
  /**
   * Write `hooks.ts` next to `output`: `defineDataHooks` from this framework's
   * entry, once per block instance and table (`useTickets`, `useTicket`).
   * Defaults to `react` when the adapters include `next`, `react` or `expo`,
   * and to `false` otherwise.
   */
  readonly hooks?: DataHooksFramework | false;
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
   * `schema.table.column` (database names), with the bucket as the value (a
   * `buckets` key or a bucket id). Generated rows type them as
   * `StoragePath<'bucket-id'>`.
   */
  readonly storagePaths?: Readonly<Record<string, string>>;
  /**
   * Function results `gen` may type as not null, keyed by function name.
   * Results are `| null` by default, since Postgres can't promise a function
   * returns a value. `notNull: true` covers the whole result (each element of a
   * set, each column of `returns table`); a list names the `returns table`
   * columns that are never null.
   */
  readonly functions?: Readonly<Record<string, FunctionConfig>>;
  /**
   * Data API grants, keyed by `table` or `schema.table`, and function `execute`
   * grants, keyed by `name(argument types)` or `schema.name(argument types)`. A
   * project with default privileges turned off grants new tables to no Data API
   * role; the `grants` SQL module writes these as the complete privilege set
   * (it revokes what is not listed), and doctor (BS106) checks them. Tables not
   * listed need `select, insert, update, delete` for `authenticated` (`select`
   * for views).
   */
  readonly expose?: Readonly<Record<string, ExposeConfig>>;
  /**
   * Modules that export `defineReadSet` results. `gen` compiles each set to a
   * function in the `read-sets` SQL module. Node imports them, so relative
   * imports need their `.ts` extension.
   */
  readonly readSets?: readonly string[];
  readonly generators?: readonly Generator[];
  /**
   * `auth.organization` without its claim (that is `claims.tenant`): the
   * organization column and how the `memberships` extension resolves it.
   */
  readonly organization?: Omit<OrganizationConfig, "claim">;
  readonly claims?: ClaimsConfig;
  readonly buckets?: Readonly<Record<string, BucketConfig>>;
  /**
   * Realtime topic templates: `{ notifications:
   * 'organization:{organizationId}:notifications' }`.
   */
  readonly topics?: Readonly<Record<string, string>>;
  readonly realtime?: RealtimeConfig;
  readonly entitlements?: EntitlementsConfig;
  /**
   * An authorization system the SQL modules, policies and doctor delegate to:
   * the `provider` access model, `entitlements.memberships` and the hook and
   * policy checks.
   */
  readonly authorization?: AuthorizationProvider;
  /**
   * Embedding columns, keyed by `table` or `schema.table`. The `vector-search`
   * SQL module writes `search_<table>(query, k)` for each, which
   * `db.$search(table, { vector, k })` calls.
   */
  readonly vectorSearch?: Readonly<Record<string, VectorSearchConfig>>;
  /**
   * The app's subject types: the entities blocks attach tags, comments, fields
   * and ranks to. Subject-bound SQL modules read this registry, the `subjects`
   * module writes `subject_title`, `subject_url` and `can_subject` from it, and
   * `gen` types `SubjectType` from its keys.
   */
  readonly subjects?: SubjectsConfig;
  /**
   * A named preset (`saas`, `crm`, ...), or a preset object: the conventions
   * that differ from the defaults and the blocks. It expands into `blocks`,
   * with the blocks they require, and the conventions it sets; the keys you set
   * win.
   */
  readonly preset?: PresetName | (string & {}) | PresetSpec;
  /**
   * The blocks to install and keep in sync (`better-supabase add`): a list of
   * names, or an object keyed by block name whose values set each block's mode,
   * schema, table and column names, permission keys and options. The foundation
   * blocks (`tenant`, `access`, `updated-at`, `rls-guard`, ...) are configured
   * here too.
   */
  readonly blocks?: readonly string[] | BlocksConfig;
  /**
   * Tables the app owns, keyed by name, created in `public` by `better-supabase
   * upgrade` with an `id`, the scope column, timestamps, row level security and
   * policies for the scope. Columns reference each other, `auth.users` or a
   * block's logical table. ADR 0040.
   */
  readonly appTables?: AppTablesConfig;
  /**
   * SQL-wide settings: the workflow, paths, and the `schema` and `api` every
   * block inherits.
   */
  readonly sql?: SqlConfig;
  readonly seed?: SeedConfig;
  /** @deprecated Use `specs`; `openapi.entry` and `openapi.output` map onto it. */
  readonly openapi?: OpenApiConfig;
  /**
   * The documents `better-supabase spec emit` writes (OpenAPI, AsyncAPI,
   * Arazzo).
   */
  readonly specs?: SpecsConfig;
  readonly doctor?: DoctorConfig;
  /** What `better-supabase gen` runs. */
  readonly gen?: GenConfig;
  readonly env?: EnvFileConfig;
  readonly scaffold?: ScaffoldConfig;
  /**
   * The integrations `init` and `add` wrote; `add` without a name sets up the
   * ones that have no files yet.
   */
  readonly integrations?: readonly IntegrationName[];
  readonly skills?: SkillsConfig;
  readonly keys?: KeysConfig;
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
  readonly recordTypes: boolean;
  readonly hooks: DataHooksFramework | false;
  readonly json: Readonly<Record<string, JsonTypeConfig>>;
  readonly codecs: Required<CodecsConfig>;
  readonly relations: Required<RelationsConfig>;
  readonly sensitive: readonly string[];
  readonly storagePaths: Readonly<Record<string, string>>;
  readonly functions: Readonly<Record<string, FunctionConfig>>;
  /** The table entries of `expose`. */
  readonly expose: Readonly<Record<string, ResolvedExpose>>;
  /** The function entries of `expose`: the roles that may execute each one. */
  readonly exposeFunctions: Readonly<Record<string, readonly ExposeRole[]>>;
  readonly readSets: readonly string[];
  readonly generators: readonly Generator[];
  /**
   * The repository extensions of the installed blocks and the columns they
   * manage; `gen` writes them as table flags.
   */
  readonly extensions: ResolvedExtensions;
  readonly claims: Required<ClaimsConfig>;
  readonly buckets: Readonly<Record<string, BucketConfig>>;
  readonly entitlements: {
    /** Unset without `entitlements.customer`. */
    readonly table?: string;
    readonly column?: string;
    readonly key: string;
    readonly memberships: "tenant" | "provider";
    readonly source: NonNullable<EntitlementsConfig["source"]>;
    readonly claim?: NonNullable<EntitlementsConfig["claim"]>;
  };
  readonly authorization?: AuthorizationProvider;
  readonly vectorSearch: readonly ({
    readonly table: string;
    readonly column: string;
    readonly distance: VectorDistance;
  } & Omit<Exclude<VectorSearchConfig, string>, "column" | "distance">)[];
  readonly subjects: SubjectsConfig;
  readonly topics: Readonly<Record<string, string>>;
  readonly realtime: Required<Omit<RealtimeConfig, "policies">> & {
    readonly policies?: TopicPoliciesConfig;
  };
  /**
   * The `preset` the config started from, as written; `blocks` already holds it
   * expanded.
   */
  readonly preset?: string | PresetSpec;
  /** `blocks` with `sql.schema` and `sql.api` applied, keyed by block name. */
  readonly blocks: AnyBlocksConfig;
  /** The installed blocks, in config order, each once. */
  readonly blockNames: readonly string[];
  /** Every install of a block, keyed by its key in `blocks`. */
  readonly instances: Readonly<Record<string, ResolvedInstance>>;
  /** `appTables`, checked; empty without any. */
  readonly appTables: AppTablesConfig;
  readonly sql: ResolvedSqlConfig;
  readonly seed: Required<SeedConfig>;
  readonly openapi: Required<OpenApiConfig>;
  readonly specs: {
    readonly entry: string;
    readonly outputs: readonly SpecOutputConfig[];
    readonly failOn: NonNullable<SpecsConfig["failOn"]>;
    readonly manifest?: string;
  };
  readonly doctor: Required<
    Omit<DoctorConfig, "claimsLimit" | "output" | "migrationSafety">
  > &
    Pick<DoctorConfig, "claimsLimit" | "output" | "migrationSafety">;
  /**
   * `tasks` stays unset without a list, so `gen` picks the steps the project
   * uses.
   */
  readonly gen: GenConfig;
  readonly env: { readonly output: string; readonly prefix?: string };
  readonly scaffold: ScaffoldConfig;
  readonly integrations: readonly IntegrationName[];
  readonly skills: SkillsConfig;
  readonly keys: KeysConfig;
  /** The environment block the CLI applied, when one was active. */
  readonly environment?: string;
}

/**
 * The columns the repository extensions of the installed blocks manage, by
 * extension; an extension whose block is not installed is `undefined`.
 */
export interface ResolvedExtensions {
  /** `updated-at`: `blocks["updated-at"].options`. */
  readonly timestamps:
    | { readonly createdAt: string; readonly updatedAt: string }
    | undefined;
  /** `trash`: `blocks.trash.options.deletedAt`. */
  readonly softDelete: { readonly column: string } | undefined;
  /**
   * `memberships`, or `auth.organization.column` without it: the organization
   * column and how a request's organization is resolved.
   */
  readonly tenant:
    | {
        readonly column: string;
        readonly onMissing?: "error" | "skip";
        readonly header?: string;
      }
    | undefined;
  /** `created-by`: `blocks["created-by"].options`. */
  readonly actor:
    | {
        readonly createdBy: string;
        readonly updatedBy: string;
        readonly impersonatedBy: string;
      }
    | undefined;
}

export type {
  AppTableInput,
  AppTablesInput,
  ApiConfig,
  AuthConfig,
  BetterSupabaseConfig,
  BlockInput,
  BlocksInput,
  DatabaseConfig,
  EnvironmentConfig,
  GenGroupConfig,
  OrganizationConfig,
  SqlInput,
  ToolingConfig,
} from "./groups.ts";
