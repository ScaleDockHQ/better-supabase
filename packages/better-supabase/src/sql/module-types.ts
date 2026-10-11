import type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationRoleSource,
} from "../config/authorization.ts";
import type {
  DisabledRow,
  ModuleMode,
  ModulesConfig,
} from "../config/modules.ts";
import type { ClaimsMeta } from "../schema/types.ts";
import type { AuditedTable } from "./audit-registrations.ts";
import type { EntitlementsSource } from "./modules/entitlements-source.ts";
import type { FunctionGrant, TableGrant } from "./modules/grants.ts";
import type { VectorSearchTable } from "./modules/vector-search.ts";

import {
  type ModuleContext,
  type ModuleContractFunction,
  type ModuleIdType,
  type ModuleNames,
} from "./context.ts";
import { type JsonSchemaCheck } from "./shared.ts";

/** The step from one module version to the next, for `sql upgrade`. */
export interface ModuleUpgrade {
  /** The installed version this step upgrades from. */
  readonly from: number;
  readonly description: string;
  /** SQL run before the module's current file, e.g. renames and backfills. */
  readonly sql: (ctx: ModuleContext) => string;
}

/**
 * A renamed module symbol. It keeps a compatibility wrapper for at least one
 * minor release, then is removed; doctor reports uses of both (BS309), and
 * the name stays reserved.
 */
export interface ModuleDeprecation {
  readonly kind: "function" | "claim" | "table" | "column";
  /** The old name: `schema.function`, a claim name, `schema.table` or `table.column`. */
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
  readonly wrapper?: (ctx: ModuleContext) => string;
}

/**
 * SQL modules for `better-supabase sql add`. Every module is idempotent
 * (`create or replace`, `if not exists`), so re-running it upgrades in place.
 */
export interface SqlModule {
  readonly name: string;
  readonly title: string;
  readonly description: string;
  /** Modules this one needs, added along with it. */
  readonly requires: readonly string[];
  /** What it needs instead when an authorization provider supplies memberships. */
  readonly providerRequires?: readonly string[];
  /**
   * The optional `authorization.functions` templates it calls under the
   * `provider` access model, such as `idsWithFor` to check another user.
   * Doctor warns (BS411) when the provider doesn't set one.
   */
  readonly providerFunctions?: readonly (keyof AuthorizationFunctions)[];
  /**
   * Modules it works with when they are installed, without needing them.
   * `ctx.installed` and `ctx.of` accept only these and what it requires;
   * `record` reaches the outbox and the audit log without listing them.
   * `*` stands for every module, for one that reads them all (`data-lifecycle`).
   */
  readonly integrates?: readonly string[];
  /** What it needs for this layout, e.g. per `sql.modules.access.model`; overrides both. */
  readonly dependencies?: (layout: ModuleLayout) => readonly string[];
  /** `schema` files go with your schemas; `test` files go to `supabase/tests`. */
  readonly target: "schema" | "test";
  /** The module with the default claim names. */
  readonly sql: string;
  /** The module for configured claim names (`config.claims`), when it reads claims. */
  readonly render?: (claims: ClaimsMeta, layout: ModuleLayout) => string;
  /** Bumped when installed databases need an upgrade step. Defaults to 1. */
  readonly version?: number;
  /** The modes `sql.modules.<name>.mode` accepts. Defaults to `managed` only. */
  readonly modes?: readonly ModuleMode[];
  /** The logical tables and columns `sql.modules.<name>.tables` and `columns` map. */
  readonly names?: ModuleNames;
  /** The functions other modules and the TypeScript side call. */
  readonly contract?: (ctx: ModuleContext) => readonly ModuleContractFunction[];
  /** Renders the module for a layout; takes precedence over `render`. */
  readonly build?: (ctx: ModuleContext, layout: ModuleLayout) => string;
  /**
   * SQL appended after the module's body that depends on the whole layout, for
   * example the grants for the tables in `expose`. Unlike `build`, it stays out
   * of what `api` wrappers and extension scans read.
   */
  readonly extras?: (ctx: ModuleContext, layout: ModuleLayout) => string;
  readonly upgrades?: readonly ModuleUpgrade[];
  readonly deprecated?: readonly ModuleDeprecation[];
  /**
   * Rows, role settings and calls that a schema diff doesn't capture. They
   * go to `better-supabase-data/` next to the schema folder and a migration
   * (`sql data`) instead of the schema file.
   */
  readonly data?: (ctx: ModuleContext, layout: ModuleLayout) => string;
  /** pgTAP files for this layout, written to the tests folder next to the `pgtap` module's. */
  readonly tests?: (
    ctx: ModuleContext,
    layout: ModuleLayout,
  ) => readonly ModuleTestFile[];
  readonly topics?: (ctx: ModuleContext) => readonly string[];
  /**
   * Functions granted to `anon` or `authenticated` only so the module's
   * policies and triggers can call them as the client. `api` writes no
   * entry point for them.
   */
  readonly internal?: readonly string[];
  readonly adoptOptional?: (
    ctx: ModuleContext,
  ) => Readonly<Record<string, readonly string[]>>;
}

/** A pgTAP file a module writes for the layout, e.g. one per audited table. */
export interface ModuleTestFile {
  /** The file name's suffix, after the module's slug. */
  readonly name: string;
  readonly sql: string;
}

export const moduleVersion = (module: SqlModule): number => module.version ?? 1;

/** A module rendered by `build`; its `sql` is the build with the defaults. */
export type ModuleDefinition = Omit<SqlModule, "sql" | "render" | "build"> & {
  readonly build: NonNullable<SqlModule["build"]>;
};

export interface ModuleFile {
  readonly module: string;
  /** `schema` and `test` files are diffed; `data` files go in a migration too. */
  readonly kind: "schema" | "data" | "test";
  readonly path: string;
  readonly contents: string;
}

export interface ModuleLayout {
  /** Directory for schema modules. Defaults to `supabase/schemas`. */
  readonly dir?: string;
  /** The declarative schema folder the diff engine loads. Defaults to `supabase/schemas`. */
  readonly schemasDir?: string;
  /** File prefix. Defaults to `900_better_supabase`. */
  readonly prefix?: string;
  /** Directory for pgTAP files. Defaults to `supabase/tests`. */
  readonly testsDir?: string;
  /** The `better_supabase.audit(...)` calls in the SQL files: the `audit` module writes a pgTAP file per table. */
  readonly auditedTables?: readonly AuditedTable[];
  /** Version stamped into the header. */
  readonly version?: string;
  /** `config.realtime.tables`: registered at the end of the `realtime-tables` module. */
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
   * `sql.modules.grants.options.fromPolicies`. Tables in `grants` keep
   * their listed privileges.
   */
  readonly policyGrants?: readonly TableGrant[];
  /** The tables the schema files create, for `sql.modules.sessions.options.policies`. */
  readonly declaredTables?: readonly string[];
  /** The declared tables with row level security on, for tables `fromPolicies` makes service-only. */
  readonly rlsTables?: readonly string[];
  /** `config.readSets`, compiled: the functions the `read-sets` module writes. */
  readonly readSets?: readonly {
    readonly name: string;
    readonly sql: string;
  }[];
  /** `config.entitlements`: where the `entitlements` module finds each tenant's Stripe customer. */
  readonly entitlements?: EntitlementsSource;
  /** `config.vectorSearch`: the tables the `vector-search` module writes a search function for. */
  readonly vectorSearch?: readonly VectorSearchTable[];
  readonly vectorSchema?: string;
  /** `config.claims`: claim names the modules read and write. */
  readonly claims?: ClaimsMeta;
  /** The authorization provider's memberships: `entitlements` reads them instead of `tenant`'s. */
  readonly entitlementsProvider?: ModuleEntitlementsProvider;
  /** The authorization provider the `access` module's `provider` model calls. */
  readonly accessProvider?: ModuleAccessProvider;
  /** `config.sql.modules`: modes, names and permission keys per module. */
  readonly modules?: ModulesConfig;
  /** The authorization provider's permission keys, for `api-keys` scopes. */
  readonly permissionCatalog?: readonly string[];
}

/** Where the `entitlements` module reads the provider's memberships, and the tables behind them. */
export interface ModuleEntitlementsProvider {
  /** The provider's name, for comments. */
  readonly name: string;
  /** The provider scope tenants are, e.g. `organization`. */
  readonly scope: string;
  readonly idType: ModuleIdType;
  /** `authorization.functions.memberIds`. */
  readonly memberIds: string;
  /** `authorization.functions.memberIdsFor`. */
  readonly memberIdsFor: string;
  readonly memberships: readonly AuthorizationMembership[];
}

/** What the `access` module's `provider` model calls. */
export interface ModuleAccessProvider {
  /** The provider's name, for comments and errors. */
  readonly name: string;
  /** The provider scope tenants are. */
  readonly scope: string;
  readonly idType: ModuleIdType;
  readonly functions: AuthorizationFunctions;
  /** The access module's `disabled` setting defaults to these. */
  readonly suspension?: {
    readonly user?: DisabledRow;
    readonly tenant?: DisabledRow;
  };
  /** An adopted `tenant` module on one of these tables reads role names the same way. */
  readonly roleSources?: readonly AuthorizationRoleSource[];
  /** How `ai-chat` applies `functions.canApprove`. */
  readonly approvals?: { readonly distinctApprover?: boolean };
}
