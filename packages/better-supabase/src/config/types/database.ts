import type {
  AccessBucketPolicy,
  BucketPolicyName,
} from "../../schema/types.ts";
import type { BucketLifecycle } from "../../storage/versioning.ts";
import type { BlockScope, SqlNaming } from "../blocks.ts";

export interface BucketConfig {
  readonly id?: string;
  readonly public?: boolean;
  /**
   * Path template with `{placeholders}`, e.g. `{organizationId}/{customerId}/logo.webp`,
   * or several when the bucket stores objects in more than one layout. A last
   * segment `{...rest}` matches one or more segments.
   */
  readonly path: string | readonly [string, ...string[]];
  /** Generated storage policy, or an access contract policy (`{ access }`). */
  readonly policy?: BucketPolicyName | AccessBucketPolicy;
  readonly fileSizeLimit?: string;
  readonly allowedMimeTypes?: readonly string[];
  /** Keep earlier object versions. `bucket.apply()` sets it; doctor (BS302) compares it. */
  readonly versioning?: boolean;
  /** When noncurrent versions expire. Needs `versioning: true`. */
  readonly lifecycle?: BucketLifecycle;
}

/**
 * How the SQL modules reach the database: `pg-delta` (Supabase Declarative
 * Schemas 2.0, `supabase db schema declarative sync`), `migra` (declarative
 * schemas 1.0, `supabase db diff`) or `migrations` (no declarative schemas:
 * the `sql` commands write the modules into a migration).
 */
export type SqlWorkflow = "pg-delta" | "migra" | "migrations";

export interface SqlConfig {
  /**
   * The workflow. Unset, better-supabase reads `supabase/config.toml`:
   * pg-delta when it enables it or nothing says otherwise, migra when it
   * turns pg-delta off or the project keeps migra's declarative schemas.
   */
  readonly workflow?: SqlWorkflow;
  /** Directory declarative schema files are written to. */
  readonly dir?: string;
  /** File name prefix, so generated files sort after yours. */
  readonly prefix?: string;
  /** Directory pgTAP files (the `pgtap` module) are written to. */
  readonly testsDir?: string;
  /**
   * The schema every module writes its functions and managed tables to,
   * unless `blocks.<name>.schema` sets its own. Defaults to `better_supabase`.
   */
  readonly schema?: string;
  /**
   * The Data API schema, such as `api`, every module writes its `security
   * invoker` wrappers to, unless `blocks.<name>.api` sets its own or
   * `false`.
   */
  readonly api?: string;
  /**
   * Who a block's rows belong to, unless `blocks.<name>.scope` sets its
   * own: `tenant` (a tenant, checked through the access contract; the
   * default), `user` (the signed-in user, with no tenants) or `none` (one
   * shared space every signed-in user reads and writes).
   */
  readonly scope?: BlockScope;
  /** Names for the tenant concept in tables, functions and columns. */
  readonly naming?: SqlNaming;
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
  readonly naming?: SqlNaming;
}

export interface SeedConfig {
  /** Module exporting `defineSeed(...)` as `seed` or default. */
  readonly entry?: string;
  /** SQL file `better-supabase seed` writes. Add it to `[db.seed] sql_paths`. */
  readonly output?: string;
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
  /**
   * Tables in `tables` whose rows belong to one user: table to its user
   * column (`{ notifications: "user_id" }`). They broadcast on a topic per
   * user, `bs:t:<schema>.<table>:u:<user id>`, which only that user
   * receives, instead of the tenant's topic.
   */
  readonly users?: Readonly<Record<string, string>>;
  /**
   * Writes the `realtime.messages` policies of the topics that `from`
   * exports (`defineTopic`) to `output`, a file in `supabase/schemas`, on
   * `better-supabase sql sync`; `sql sync --check` fails when it is stale.
   */
  readonly policies?: TopicPoliciesConfig;
  /**
   * Broadcast triggers that `sql sync` writes to `policies.output` next to
   * the policies: each one calls `better_supabase.broadcast_topic()` (the
   * `realtime-tables` module) for a topic that `policies.from` exports.
   */
  readonly triggers?: readonly TopicTriggerConfig[];
}

/** One `realtime.triggers` entry: a table whose row changes go to a topic. */
export interface TopicTriggerConfig {
  /** The template of a topic that `realtime.policies.from` exports. */
  readonly topic: string;
  /** `table` or `schema.table`. */
  readonly table: string;
  /** The column per placeholder. Defaults to the placeholder in snake_case. */
  readonly values?: Readonly<Record<string, string>>;
  /** Defaults to all three. */
  readonly events?: readonly ("insert" | "update" | "delete")[];
  /** The broadcast event name. Defaults to the operation. */
  readonly event?: string;
}

/** `realtime.policies`: where topic policies come from and go. */
export interface TopicPoliciesConfig {
  /** Modules that export `defineTopic` results. Node imports them. */
  readonly from: readonly string[];
  /** The SQL file to write, such as `supabase/schemas/905_topics.sql`. */
  readonly output: string;
}

/** pgvector distance: `<=>` (cosine), `<->` (l2) or `<#>` (negative inner product). */
export type VectorDistance = "cosine" | "l2" | "inner_product";

/** The embedding column, or the column and its distance (default `cosine`). */
export type VectorSearchConfig =
  | string
  | {
      readonly column: string;
      readonly distance?: VectorDistance;
      /** The column's pgvector type. Defaults to `vector`. */
      readonly type?: "vector" | "halfvec";
      /** The primary key column `db.$search({ score: true })` merges by. Defaults to `id`. */
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
      /** A SQL expression over the row `t` the score is multiplied by, such as `t.priority`. */
      readonly boost?: string;
      /** Columns `db.$search({ filter })` narrows before ranking. */
      readonly prefilter?: readonly string[];
      /**
       * A SQL condition over the row `t` every candidate must meet, applied
       * before ranking: ranges, a parent row, such as
       * `t.expires_at > now() and exists (select 1 from public.folders f where f.id = t.folder_id and not f.disabled)`.
       */
      readonly predicate?: string;
      /** How `boost` combines with the score: `multiply` (default) or `add`. */
      readonly boostMode?: "multiply" | "add";
      /** A SQL `order by` list over the row `t` that breaks score ties, such as `t.created_at desc`. */
      readonly order?: string;
    };
