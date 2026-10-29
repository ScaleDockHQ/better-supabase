import type {
  AccessBucketPolicy,
  BucketPolicyName,
} from "../../schema/types.ts";
import type { BucketLifecycle } from "../../storage/versioning.ts";
import type {
  BlockScope,
  OwnTablePolicies,
  TenantScopeConfig,
} from "../blocks.ts";

export interface BucketConfig {
  readonly id?: string;
  readonly public?: boolean;
  /**
   * Path template with `{placeholders}`, e.g.
   * `{organizationId}/{customerId}/logo.webp`, or several when the bucket
   * stores objects in more than one layout. A last segment `{...rest}` matches
   * one or more segments.
   */
  readonly path: string | readonly [string, ...string[]];
  /** Generated storage policy, or an access contract policy (`{ access }`). */
  readonly policy?: BucketPolicyName | AccessBucketPolicy;
  readonly fileSizeLimit?: string;
  readonly allowedMimeTypes?: readonly string[];
  /**
   * Keep earlier object versions. `bucket.apply()` sets it; doctor (BS302)
   * compares it.
   */
  readonly versioning?: boolean;
  /** When noncurrent versions expire. Needs `versioning: true`. */
  readonly lifecycle?: BucketLifecycle;
}

/**
 * How the SQL modules reach the database: `pg-delta` (Supabase Declarative
 * Schemas 2.0, `supabase db schema declarative sync`), `migra` (declarative
 * schemas 1.0, `supabase db diff`) or `migrations` (no declarative schemas: the
 * `sql` commands write the modules into a migration).
 */
export type SqlWorkflow = "pg-delta" | "migra" | "migrations";

export interface SqlConfig {
  /**
   * The workflow. Unset, better-supabase reads `supabase/config.toml`: pg-delta
   * when it enables it or nothing says otherwise, migra when it turns pg-delta
   * off or the project keeps migra's declarative schemas.
   */
  readonly workflow?: SqlWorkflow;
  /** Directory declarative schema files are written to. */
  readonly dir?: string;
  /** File name prefix, so generated files sort after yours. */
  readonly prefix?: string;
  /** Directory pgTAP files (the `pgtap` module) are written to. */
  readonly testsDir?: string;
  /**
   * The schema every module writes its functions and managed tables to, unless
   * `blocks.<name>.schema` sets its own. Defaults to `better_supabase`.
   */
  readonly schema?: string;
  /**
   * The Data API schema, such as `api`, every module writes its `security
   * invoker` wrappers to, unless `blocks.<name>.api` sets its own or `false`.
   */
  readonly api?: string;
  /**
   * Who a block's rows belong to, unless `blocks.<name>.owner` sets its own:
   * `tenant` (a tenant, checked through the access contract; the default),
   * `user` (the signed-in user, with no tenants) or `none` (one shared space
   * every signed-in user reads and writes).
   */
  readonly scope?: BlockScope;
  /**
   * Whose policies govern the app's tables a block runs over, unless
   * `blocks.<name>.ownTablePolicies` sets its own: `block` (the default) or
   * `app`, which keeps every `bsb_` policy, permissive or restrictive, off
   * them.
   */
  readonly ownTablePolicies?: OwnTablePolicies;
  /**
   * The restrictive `bsb_tenant_scope_*` policies, unless
   * `blocks.<name>.tenantScope` sets its own.
   */
  readonly tenantScope?: TenantScopeConfig;
  readonly tenantColumn?: string;
}

/** `sql` with defaults applied. */
export interface ResolvedSqlConfig {
  /** Unset when the config leaves it to `supabase/config.toml`. */
  readonly workflow?: SqlWorkflow;
  readonly dir: string;
  readonly prefix: string;
  readonly testsDir: string;
  /** Unset means `tenant`. */
  readonly scope?: BlockScope;
  readonly tenantColumn?: string;
  /**
   * `schema`, `api`, `ownTablePolicies` and `tenantScope` as the config sets
   * them, for blocks added after the config was resolved. Unset without any.
   */
  readonly blockDefaults?: SqlBlockDefaults;
}

/** The `sql` keys every block takes unless it sets its own. */
export type SqlBlockDefaults = Pick<
  SqlConfig,
  "schema" | "api" | "ownTablePolicies" | "tenantScope"
>;

export interface SeedConfig {
  /** Module exporting `defineSeed(...)` as `seed` or default. */
  readonly entry?: string;
  /** SQL file `better-supabase db seed` writes. Add it to `[db.seed] sql_paths`. */
  readonly output?: string;
  /**
   * Module exporting `defineTenantSeed(...)` as `seed` or default.
   * `better-supabase db seed --tenant <slug>` applies it to one tenant.
   */
  readonly perTenant?: string;
}

export interface RealtimeConfig {
  /**
   * Tables that broadcast a change signal for live queries (`table` or
   * `schema.table`). Tenant tables broadcast per tenant. Install the triggers
   * with `better-supabase add realtime-tables`.
   */
  readonly tables?: readonly string[];
  /**
   * Tables in `tables` without a tenant column. They broadcast on one topic
   * every signed-in user receives. With the `tenant` plugin, a table that lacks
   * the tenant column and is not listed here fails to install.
   */
  readonly global?: readonly string[];
  /**
   * Tables in `tables` whose rows belong to one user: table to its user column
   * (`{ notifications: "user_id" }`). They broadcast on a topic per user,
   * `bsb:t:<schema>.<table>:u:<user id>`, which only that user receives,
   * instead of the tenant's topic.
   */
  readonly users?: Readonly<Record<string, string>>;
  /**
   * Writes the `realtime.messages` policies of the topics that `from` exports
   * (`defineTopic`) to `output`, a file in `supabase/schemas`, on
   * `better-supabase upgrade`; `upgrade --check` fails when it is stale.
   */
  readonly policies?: TopicPoliciesConfig;
  /**
   * Broadcast triggers that `upgrade` writes to `policies.output` next to the
   * policies, through the topic's `trigger()`, for topics that `policies.from`
   * exports. A trigger with column values, one topic, a `keys` or `row` payload
   * and one event name calls `better_supabase.broadcast_topic()` (the
   * `realtime-tables` module); any other gets a generated function.
   */
  readonly triggers?: readonly TopicTriggerConfig[];
}

export interface TopicTriggerLookupConfig {
  readonly from: string;
  readonly via: TopicTriggerValueConfig;
  readonly select: string;
  readonly key?: string;
}

export type TopicTriggerValueConfig = string | TopicTriggerLookupConfig;

export type TopicTriggerPayloadValueConfig =
  | TopicTriggerValueConfig
  | { readonly sql: string };

export interface TopicTriggerTopicConfig {
  readonly topic: string;
  readonly values?: Readonly<Record<string, TopicTriggerValueConfig>>;
}

/** One `realtime.triggers` entry: a table whose row changes go to a topic. */
export interface TopicTriggerConfig {
  /** The template of a topic that `realtime.policies.from` exports. */
  readonly topic: string;
  /** `table` or `schema.table`. */
  readonly table: string;
  /**
   * The column or lookup per placeholder. Defaults to the placeholder in
   * snake_case. A row whose topic comes out null is not sent to it.
   */
  readonly values?: Readonly<Record<string, TopicTriggerValueConfig>>;
  /** Defaults to all three. */
  readonly events?: readonly ("insert" | "update" | "delete")[];
  /**
   * The broadcast event name, or one per operation (`{ insert: "created",
   * delete: "deleted" }`). Defaults to the operation.
   */
  readonly event?:
    | string
    | {
        readonly insert?: string;
        readonly update?: string;
        readonly delete?: string;
      };
  /**
   * `"keys"` (default) sends the primary key and the placeholder values.
   * `"row"` sends the whole row, which bypasses column grants. An object is the
   * payload itself: each key is a column, a lookup, or `{ sql }`, an expression
   * on the row `{row}` (`tg_op` is the operation).
   */
  readonly payload?:
    | "keys"
    | "row"
    | Readonly<Record<string, TopicTriggerPayloadValueConfig>>;
  readonly topics?: readonly TopicTriggerTopicConfig[];
  readonly functionSchema?: string;
  /**
   * `{ changed: ["status"] }` sends an UPDATE only when one of these columns
   * changed. Inserts and deletes always send.
   */
  readonly when?: { readonly changed: readonly string[] };
}

/** `realtime.policies`: where topic policies come from and go. */
export interface TopicPoliciesConfig {
  /** Modules that export `defineTopic` results. Node imports them. */
  readonly from: readonly string[];
  /** The SQL file to write, such as `supabase/schemas/905_topics.sql`. */
  readonly output: string;
}

/**
 * Pgvector distance: `<=>` (cosine), `<->` (l2) or `<#>` (negative inner
 * product).
 */
export type VectorDistance = "cosine" | "l2" | "inner_product";

/** The embedding column, or the column and its distance (default `cosine`). */
export type VectorSearchConfig =
  | string
  | {
      readonly column: string;
      readonly distance?: VectorDistance;
      /** The column's pgvector type. Defaults to `vector`. */
      readonly type?: "vector" | "halfvec";
      /**
       * The primary key column `db.$search({ score: true })` merges by.
       * Defaults to `id`.
       */
      readonly key?: string;
      /**
       * Fuses a full-text ranking over a `tsvector` column with the vector
       * ranking (reciprocal rank fusion), for `db.$search({ text })`.
       */
      readonly hybrid?: {
        readonly tsvector: string;
        /** The query's text search configuration. Defaults to `simple`. */
        readonly config?: string;
        /** The RRF constant. Defaults to 60. */
        readonly k?: number;
      };
      /**
       * A SQL expression over the row `t` the score is multiplied by, such as
       * `t.priority`.
       */
      readonly boost?: string;
      /** Columns `db.$search({ filter })` narrows before ranking. */
      readonly prefilter?: readonly string[];
      /**
       * A SQL condition over the row `t` every candidate must meet, applied
       * before ranking: ranges, a parent row, such as `t.expires_at > now() and
       * exists (select 1 from public.folders f where f.id = t.folder_id and not
       * f.disabled)`.
       */
      readonly predicate?: string;
      /** How `boost` combines with the score: `multiply` (default) or `add`. */
      readonly boostMode?: "multiply" | "add";
      /**
       * A SQL `order by` list over the row `t` that breaks score ties, such as
       * `t.created_at desc`.
       */
      readonly order?: string;
    };
