import type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationOperation,
  AuthorizationRoleSource,
} from "../config/authorization.ts";
import type {
  AnyBlocksConfig,
  BlockScope,
  DisabledRow,
  BlockMode,
} from "../config/blocks.ts";
import type { ResolvedInstance } from "../config/instances.ts";
import type { CatalogPolicy } from "../config/snapshot.ts";
import type { AppTablesConfig } from "../config/types/app-tables.ts";
import type { SubjectsConfig } from "../config/types/subjects.ts";
import type { ClaimsMeta } from "../schema/types.ts";
import type { AuditedTable } from "./audit-registrations.ts";
import type {
  BlockSqlContext,
  BlockSqlContractFunction,
  BlockSqlIdType,
  BlockSqlNames,
} from "./context.ts";
import type { BlockContributes } from "./contributions.ts";
import type { DeclaredForeignKey } from "./foreign-keys.ts";
import type { EntitlementsSource } from "./modules/entitlements-source.ts";
import type { FunctionGrant, TableGrant } from "./modules/grants.ts";
import type { VectorSearchTable } from "./modules/vector-search.ts";
import type { JsonSchemaCheck } from "./shared.ts";

/** The step from one module version to the next, for `upgrade`. */
export interface BlockSqlUpgrade {
  /** The installed version this step upgrades from. */
  readonly from: number;
  readonly description: string;
  /** SQL run before the module's current file, e.g. renames and backfills. */
  readonly sql: (ctx: BlockSqlContext) => string;
}

/**
 * A renamed module symbol. It keeps a compatibility wrapper for at least one
 * minor release, then is removed; doctor reports uses of both (BS309), and the
 * name stays reserved.
 */
export interface BlockSqlDeprecation {
  readonly kind: "function" | "claim" | "table" | "column";
  /**
   * The old name: `schema.function`, a claim name, `schema.table` or
   * `table.column`.
   */
  readonly symbol: string;
  /** What to use instead. */
  readonly use: string;
  /** The package version that deprecated it. */
  readonly since: string;
  /** The package version that removed it; until then `wrapper` is written. */
  readonly removed?: string;
  /**
   * The compatibility wrapper the module file keeps, e.g. a function with the
   * old name that calls the new one and a `comment on function ... is
   * 'deprecated: use X'`.
   */
  readonly wrapper?: (ctx: BlockSqlContext) => string;
}

/**
 * SQL modules for `better-supabase add`. Every module is idempotent (`create or
 * replace`, `if not exists`), so re-running it upgrades in place.
 */
export interface BlockSql {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  /** Modules this one needs, added along with it. */
  readonly requires: readonly string[];
  /**
   * The scopes the module runs in. A module that needs tenants declares
   * `["tenant"]`; unset, it runs in every scope. Outside `tenant` scope a
   * module needs neither `tenant` nor `access`, so they drop from `requires`.
   */
  readonly scopes?: readonly BlockScope[];
  /**
   * A module this one renders and is numbered ahead of, for a module that owns
   * a subject table the `case` checks of `comments` or `attachments` name, or
   * that `search` puts its index trigger on. The file takes the number before
   * it, so later files keep theirs.
   */
  readonly before?: string;
  /** What it needs instead when an authorization provider supplies memberships. */
  readonly providerRequires?: readonly string[];
  /**
   * The optional `authorization.functions` templates it calls under the
   * `provider` access model, such as `idsWithFor` to check another user. Doctor
   * warns (BS411) when the provider doesn't set one.
   */
  readonly providerFunctions?: readonly (keyof AuthorizationFunctions)[];
  /**
   * Modules it works with when they are installed, without needing them.
   * `ctx.installed` and `ctx.of` accept only these and what it requires;
   * `record` reaches the outbox and the audit log without listing them. `*`
   * stands for every module, for one that reads them all (`data-lifecycle`).
   */
  readonly integrates?: readonly string[];
  /**
   * What it adds to generic blocks (approvals, bulk actions, share links and
   * the subject functions) that read it without naming it. Each function gets
   * this block's context and the generic block's.
   */
  readonly contributes?: BlockContributes;
  /**
   * What it needs for this layout, e.g. per `blocks.permissions.model`;
   * overrides both.
   */
  readonly dependencies?: (layout: BlockSqlLayout) => readonly string[];
  /** `schema` files go with your schemas; `test` files go to `supabase/tests`. */
  readonly target: "schema" | "test";
  /** The module built for the default layout. */
  readonly sql: string;
  /** Bumped when installed databases need an upgrade step. Defaults to 1. */
  readonly version?: number;
  /** The modes `blocks.<name>.ownership` accepts. Defaults to `managed` only. */
  readonly modes?: readonly BlockMode[];
  /**
   * The logical tables and columns `blocks.<name>.tables` and `columns` map. A
   * table's entry is its spec; its `app` says whether it can be a table the app
   * already has (`BlockSqlAppTable`).
   */
  readonly names?: BlockSqlNames;
  /** The functions other modules and the TypeScript side call. */
  readonly contract?: (
    ctx: BlockSqlContext,
  ) => readonly BlockSqlContractFunction[];
  /** Renders the module for a layout. */
  readonly build: (ctx: BlockSqlContext, layout: BlockSqlLayout) => string;
  /**
   * SQL appended after the module's body that depends on the whole layout, for
   * example the grants for the tables in `expose`. Unlike `build`, it stays out
   * of what `api` wrappers and extension scans read.
   */
  readonly extras?: (ctx: BlockSqlContext, layout: BlockSqlLayout) => string;
  readonly upgrades?: readonly BlockSqlUpgrade[];
  readonly deprecated?: readonly BlockSqlDeprecation[];
  /**
   * Rows, role settings and calls that a schema diff doesn't capture. They go
   * to `better-supabase-data/` next to the schema folder and a migration (`sql
   * data`) instead of the schema file.
   */
  readonly data?: (ctx: BlockSqlContext, layout: BlockSqlLayout) => string;
  /**
   * PgTAP files for this layout, written to the tests folder next to the
   * `pgtap` module's.
   */
  readonly tests?: (
    ctx: BlockSqlContext,
    layout: BlockSqlLayout,
  ) => readonly BlockSqlTestFile[];
  readonly topics?: (ctx: BlockSqlContext) => readonly string[];
  readonly permissionKeys?: (
    ctx: BlockSqlContext,
  ) => readonly {
    readonly action: string;
    readonly key: string;
    readonly scope: "tenant" | "platform";
    readonly setting: string;
  }[];
  /**
   * Functions granted to `anon` or `authenticated` only so the module's
   * policies and triggers can call them as the client. `api` writes no entry
   * point for them.
   */
  readonly internal?: readonly string[];
  /**
   * Soft-delete columns, as logical `table.column`: a write can set them to
   * hide a row but never clear them again, so doctor BS213 doesn't count them
   * as columns that grant access.
   */
  readonly hidingColumns?: readonly string[];
  /** The app's tables outside `names.tables` that the module writes columns of. */
  readonly appSubjectTables?: (
    ctx: BlockSqlContext,
  ) => readonly BlockSqlAppSubjectTable[];
}

/**
 * How one of a module's tables can be a table the app already has (ADR 0098).
 * It sits on the table's entry in `names.tables` (`app`), next to `columns`,
 * `optional` and `typed`, which together make the table's spec:
 *
 * - The required columns are those in `columns` that aren't `optional` or
 *   `unused`. The module adds each one the app's table lacks with `add column
 *   if not exists`, nullable unless it has a default, and doctor (BS330) and
 *   `add --adopt` check and propose them.
 * - The optional columns may be mapped to `null` in `blocks.<name>.columns`; the
 *   module then leaves out the feature that needs them.
 * - The `typed` columns may be an enum or a domain on the app's table; the module
 *   writes them through `ctx.cast`.
 *
 * When `layout.ownTables` has the table, `ctx.owns(table)` is false: the module
 * skips its `create table` and lays its functions, policies, triggers and
 * indexes over the app's table. A table whose entry has no `app` is always the
 * module's: it creates it, and a table of that name in the app's schema is an
 * error.
 */
export interface BlockSqlAppTable {
  /**
   * The app's table only when `blocks.<name>.tables` maps it. Unmapped, the
   * module creates its own, so an app table with the default name is an error.
   */
  readonly onlyWhenMapped?: boolean;
  /**
   * Logical columns this configuration doesn't use, such as the secret column
   * when secrets live in Vault. They are neither required nor checked.
   */
  readonly unused?: (ctx: BlockSqlContext) => readonly string[];
}

/**
 * A table of the app's outside `names.tables` that a module writes columns of,
 * such as a subject table that `blocks.<name>.on.<type>` names. A null column
 * is mapped away; doctor and `upgrade` check the others exist.
 */
export interface BlockSqlAppSubjectTable {
  readonly logical: string;
  readonly schema: string;
  readonly table: string;
  readonly columns: Readonly<Record<string, string | null>>;
}

/** A pgTAP file a module writes for the layout, e.g. one per audited table. */
export interface BlockSqlTestFile {
  /** The file name's suffix, after the module's slug. */
  readonly name: string;
  readonly sql: string;
}

export const blockSqlVersion = (module: BlockSql): number =>
  module.version ?? 1;

/** A module as written; `built` adds `sql`, the build for the default layout. */
export type BlockSqlDefinition = Omit<BlockSql, "sql">;

export interface BlockSqlFile {
  readonly module: string;
  /** The instance, when it installs `module` under another name. */
  readonly instance?: string;
  /** `schema` and `test` files are diffed; `data` files go in a migration too. */
  readonly kind: "schema" | "data" | "test";
  readonly path: string;
  readonly contents: string;
}

export interface BlockSqlLayout {
  /**
   * `config.instances`. An instance that installs a block under another name
   * renders its own files; `modules` holds the instances named after their
   * block.
   */
  readonly instances?: Readonly<Record<string, ResolvedInstance>>;
  /** Directory for schema modules. Defaults to `supabase/schemas`. */
  readonly dir?: string;
  /**
   * The declarative schema folder the diff engine loads. Defaults to
   * `supabase/schemas`.
   */
  readonly schemasDir?: string;
  /** File prefix. Defaults to `900_better_supabase`. */
  readonly prefix?: string;
  /** Directory for pgTAP files. Defaults to `supabase/tests`. */
  readonly testsDir?: string;
  /**
   * The `better_supabase.audit(...)` calls in the SQL files: the `audit` module
   * writes a pgTAP file per table.
   */
  readonly auditedTables?: readonly AuditedTable[];
  /**
   * Ignored: the header names only the module, so a release doesn't rewrite
   * every file. The `@bsb-block name@N` marker carries the module version.
   *
   * @deprecated Remove it; it has no effect.
   */
  readonly version?: string;
  /**
   * `config.realtime.tables`: registered at the end of the `realtime-tables`
   * module.
   */
  readonly realtimeTables?: readonly string[];
  /** `config.realtime.global`: tables registered with `tenant_column => null`. */
  readonly realtimeGlobal?: readonly string[];
  /** `config.realtime.users`: tables registered with `user_column`. */
  readonly realtimeUsers?: Readonly<Record<string, string>>;
  /** Tenant column passed to `track_realtime` for the other tables. */
  readonly tenantColumn?: string;
  /** Check constraints for the `jsonb-schemas` module. */
  readonly jsonSchemas?: readonly JsonSchemaCheck[];
  /** `config.expose`: the grants the `grants` module writes. */
  readonly grants?: readonly TableGrant[];
  /** `config.expose` functions: the roles that may execute each one. */
  readonly functionGrants?: readonly FunctionGrant[];
  /**
   * Grants the permissive policies in the schema files imply, for
   * `blocks['grants'].options.fromPolicies`. Tables in `grants` keep their
   * listed privileges.
   */
  readonly policyGrants?: readonly TableGrant[];
  /**
   * The tables the schema files create, for
   * `blocks['sessions'].options.policies`.
   */
  readonly declaredTables?: readonly string[];
  /**
   * `schema.table` of each table the app already has, to the schema file that
   * creates it or `database`. A block leaves these tables alone and adds only
   * the columns it needs, and an app table refuses their names.
   */
  readonly ownTables?: Readonly<Record<string, string>>;
  /** The columns of the tables in `ownTables`, where they are known. */
  readonly ownColumns?: Readonly<Record<string, readonly string[]>>;
  /**
   * The trigger that already keeps `updated_at` current on a table in
   * `ownTables`, by `schema.table`. A block adds no `updated_at` trigger
   * there.
   */
  readonly ownUpdatedAtTriggers?: Readonly<Record<string, string>>;
  /**
   * The app's own policies on a table in `ownTables`, by `schema.table`. A
   * block adds no permissive policy that one of them already covers.
   */
  readonly ownPolicies?: Readonly<Record<string, readonly CatalogPolicy[]>>;
  /**
   * The declared tables with row level security on, for tables `fromPolicies`
   * makes service-only.
   */
  readonly rlsTables?: readonly string[];
  /**
   * The foreign keys the schema files declare, for
   * `blocks.memberships.options.sameTenant.auto`.
   */
  readonly foreignKeys?: readonly DeclaredForeignKey[];
  /**
   * Each declared table's columns, `schema.table` to names, for
   * `sameTenant.auto`.
   */
  readonly declaredColumns?: Readonly<Record<string, readonly string[]>>;
  /** `config.readSets`, compiled: the functions the `read-sets` module writes. */
  readonly readSets?: readonly {
    readonly name: string;
    readonly sql: string;
  }[];
  /**
   * `config.entitlements`: where the `entitlements` module finds each tenant's
   * Stripe customer.
   */
  readonly entitlements?: EntitlementsSource;
  /**
   * `config.vectorSearch`: the tables the `vector-search` module writes a
   * search function for.
   */
  readonly vectorSearch?: readonly VectorSearchTable[];
  readonly vectorSchema?: string;
  /** `config.claims`: claim names the modules read and write. */
  readonly claims?: ClaimsMeta;
  /**
   * The authorization provider's memberships: `entitlements` reads them instead
   * of `tenant`'s.
   */
  readonly entitlementsProvider?: BlockSqlEntitlementsProvider;
  /** The authorization provider the `access` module's `provider` model calls. */
  readonly accessProvider?: BlockSqlAccessProvider;
  /** `config.blocks`: modes, names and permission keys per module. */
  readonly modules?: AnyBlocksConfig;
  /** `sql.scope`: the scope of every block that sets none. Defaults to `tenant`. */
  readonly scope?: BlockScope;
  /** `config.records`: the app-wide subject registry (ADR 0020). */
  readonly subjects?: SubjectsConfig;
  /**
   * `config.appTables`: the tables the app owns, rendered after the blocks (ADR
   * 0040).
   */
  readonly appTables?: AppTablesConfig;
  /** The authorization provider's permission keys, for `api-keys` scopes. */
  readonly permissionCatalog?: readonly string[];
  /**
   * `authorization.delegation.scopes`: the access module's `scope_permissions`
   * (with `blocks.permissions.scopes` merged over it).
   */
  readonly delegationScopes?: Readonly<Record<string, readonly string[]>>;
}

/**
 * Where the `entitlements` module reads the provider's memberships, and the
 * tables behind them.
 */
export interface BlockSqlEntitlementsProvider {
  /** The provider's name, for comments. */
  readonly name: string;
  /** The provider scope tenants are, e.g. `organization`. */
  readonly scope: string;
  readonly idType: BlockSqlIdType;
  /** `authorization.functions.memberIds`. */
  readonly memberIds: string;
  /** `authorization.functions.memberIdsFor`. */
  readonly memberIdsFor: string;
  readonly memberships: readonly AuthorizationMembership[];
}

/** What the `access` module's `provider` model calls. */
export interface BlockSqlAccessProvider {
  /** The provider's name, for comments and errors. */
  readonly name: string;
  /** The provider scope tenants are. */
  readonly scope: string;
  /** Every scope it declares, for `on.<type>.scope`. */
  readonly scopes?: readonly string[];
  readonly idType: BlockSqlIdType;
  readonly functions: AuthorizationFunctions;
  /** The access module's `disabled` setting defaults to these. */
  readonly suspension?: {
    readonly user?: DisabledRow;
    readonly tenant?: DisabledRow;
  };
  /**
   * An adopted `tenant` module on one of these tables reads role names the same
   * way.
   */
  readonly roleSources?: readonly AuthorizationRoleSource[];
  /** How `ai-chat` applies `functions.canApprove`. */
  readonly approvals?: { readonly distinctApprover?: boolean };
  /** The provider's operations table; `operationPermission` reads it. */
  readonly operations?: Readonly<Record<string, AuthorizationOperation>>;
}

/** Whether any of the module's tables can be a table the app already has. */
export function runsOverAppTables(module: Pick<BlockSql, "names">): boolean {
  return Object.values(module.names?.tables ?? {}).some(
    (table) => table.app !== undefined,
  );
}
