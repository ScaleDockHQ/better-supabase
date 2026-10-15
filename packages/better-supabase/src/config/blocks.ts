import type { BlockOptionsRegistry } from "../blocks/options-registry.ts";

/**
 * `blocks` in `better-supabase.config.ts`: how each SQL module maps onto
 * the app's database. A module's contract (the functions other modules and
 * the TypeScript side call) stays the same in every mode; only the tables
 * behind it change.
 */

/**
 * `managed`: the module owns its tables. `adopt`: the module writes its functions
 * and views over tables the app already has (`tables` and `columns`), never
 * `create table`. `custom`: the app implements the contract functions itself;
 * the module writes nothing and doctor checks the signatures (BS307).
 */
export type BlockMode = "managed" | "adopt" | "custom";

/** Options every module takes; `Options` types `options` (`blocks.<module>.options`). */
export interface BlockConfig<
  Options extends object = Readonly<Record<string, unknown>>,
> {
  readonly mode?: BlockMode;
  /** Schema of the module's functions and managed tables. Defaults to `sql.schema`, then `better_supabase`. */
  readonly schema?: string;
  /**
   * Logical table to `table` or `schema.table`, e.g.
   * `{ memberships: 'public.organization_users' }`. An unqualified name is in
   * `schema`. `null` marks an optional table the app doesn't have.
   */
  readonly tables?: Readonly<Record<string, string | null>>;
  /**
   * Logical table to logical column to column name, e.g.
   * `{ memberships: { tenant: 'organization_id', role: 'role_id' } }`.
   * `null` marks an optional column the adopted table doesn't have.
   */
  readonly columns?: Readonly<
    Record<string, Readonly<Record<string, string | null>>>
  >;
  /** Type of tenant ids: `uuid` (default), `text`, `bigint` or `integer`. */
  readonly idType?: string;
  /**
   * Module action to permission key, checked through the access contract, e.g.
   * `{ invite: 'organization.members.invite' }`.
   */
  readonly permissions?: Readonly<Record<string, string>>;
  /**
   * Module-specific options, typed from the block manifest's options
   * schema; each module's docs page lists them.
   */
  readonly options?: Options;
  /**
   * The app's optional `before_*` and `after_*` functions the module calls
   * when they exist, e.g. `after_organization_create(organization, user)`. They are
   * looked up in `schema` (default `public`); `functions` maps a hook name
   * to another function, e.g. `{ after_organization_create: 'app.seed_organization' }`.
   */
  readonly hooks?: {
    readonly schema?: string;
    readonly functions?: Readonly<Record<string, string>>;
  };
  /**
   * Whether the module writes its events to the outbox (`emit_event`) when
   * the `outbox` module is installed. Defaults to true.
   */
  readonly events?: boolean;
  /**
   * Whether the module writes its actions to the audit log (`audit_event`)
   * when the `audit` module is installed. Defaults to true.
   */
  readonly audit?: boolean;
  /**
   * A schema for the Data API, such as `api`: the module writes a
   * `security invoker` wrapper there for each of its functions that `anon`
   * or `authenticated` may execute (or only those in `functions`), so
   * `rpcTransport(supabase, { schema: "api" })` reaches them without
   * exposing the module schema (doctor BS312). Defaults to `sql.api`;
   * `false` writes no wrappers even when `sql.api` is set.
   */
  readonly api?:
    | string
    | false
    | { readonly schema: string; readonly functions?: readonly string[] };
}

/**
 * Where the active tenant of a request comes from. Every source counts only
 * while the caller is a member, so a stale claim or setting grants nothing.
 */
export type ActiveTenantSource =
  /** The `claims.tenant` claim, written by `switch_organization`. */
  | "claim"
  /**
   * A TypeScript resolver (`ServerOptions.tenant`), e.g. from a URL slug (the
   * default). The server sends it as the `x-bs-tenant` header, then the
   * `claims.tenant` claim is the fallback.
   */
  | "resolver"
  /** A profile column keyed by the user id, e.g. `public.profiles.active_organization_id`. */
  | { readonly profileColumn: string; readonly key?: string };

/** URL tenancy: the tenant comes from the request (a slug), not a stored setting. */
export const DEFAULT_ACTIVE_TENANT: ActiveTenantSource = "resolver";

/**
 * The access contract every module checks permissions through:
 * `can(scope, id, permission)`, `tenant_ids_with(permission)`,
 * `is_platform(permission)` and `can_user(user, scope, id, permission)`.
 */
/**
 * A table whose row says whether a tenant or a user is active. Needs
 * `disabledAt`, `status` with `active`, or both.
 */
export interface DisabledRow {
  /** `schema.table`. */
  readonly table: string;
  /** The column holding the tenant id or the user id. */
  readonly id: string;
  /** A nullable timestamp column; a row with a value is disabled. */
  readonly disabledAt?: string;
  /** A status column; only a row whose value is in `active` is active. */
  readonly status?: string;
  readonly active?: readonly string[];
}

export interface AccessBlockConfig<
  Options extends object = Readonly<Record<string, unknown>>,
> extends BlockConfig<Options> {
  /**
   * `roles`: a fixed role list from `roles` (the default without
   * `authorization`; with it, `provider` is the default). `catalog`: role,
   * permission and override tables (`tables.roles`, `permissions`,
   * `rolePermissions`, `overrides`, `platformAssignments`). `provider`: the
   * functions of the config's `authorization` provider. `custom`:
   * expression templates in `functions`.
   */
  readonly model?: "roles" | "catalog" | "provider" | "custom";
  /**
   * `roles` model: role name to permission keys. `*` grants everything and
   * `prefix.*` a prefix. Defaults to owner, admin, member and viewer.
   */
  readonly roles?: Readonly<Record<string, readonly string[]>>;
  /**
   * `custom` model: SQL expressions with `{scope}`, `{id}`, `{permission}`
   * and `{user}` placeholders, e.g.
   * `{ can: 'public.authorize_scope({scope}::public.scope_type, {id}, {permission})' }`.
   */
  readonly functions?: {
    readonly can?: string;
    readonly tenantIdsWith?: string;
    readonly isPlatform?: string;
    readonly canUser?: string;
    /**
     * `{tenant}` and `{role}`: whether the caller may assign the role.
     * Required by the `custom` model. The `provider` model defaults to the
     * provider's `canAssign`; without either, only the service role assigns
     * roles unless the `tenant` module is installed, and doctor BS411 warns.
     */
    readonly canAssign?: string;
    /**
     * `{user}`, `{tenant}` and `{role}`: whether that user may assign the
     * role, for SQL that acts later for a stored user (an invitation accept
     * checking the inviter again), as `can_assign_as`. The `provider` model
     * defaults to the provider's `canAssignFor`.
     */
    readonly canAssignFor?: string;
    /**
     * `{permission}` and `{tenant}`: the user ids that hold the permission
     * in the tenant, for the `custom` model's notification audiences.
     */
    readonly holdersOf?: string;
    /** `{user}`: the permission claim for the access token hook. */
    readonly permissionClaims?: string;
  };
  /**
   * `roles` model: the JWT claim holding the caller's platform permission
   * keys (an array). Defaults to `platform_permissions`.
   */
  readonly platformClaim?: string;
  /**
   * OAuth scope to the permission keys it grants a delegated token (a
   * `client_id`, or an `act` chain that is not a support or impersonation
   * level). The access functions refuse every key the token's scopes don't
   * map to, whatever the user holds. A scope without an entry grants the
   * key with its own name; map a scope to `["*"]` to grant everything.
   * Merged over `authorization.delegation.scopes`.
   */
  readonly scopes?: Readonly<Record<string, readonly string[]>>;
  /**
   * What disables a tenant or a user. A string is a column that disables
   * when set, as `schema.table.column`, keyed by the table's `id` (tenant)
   * or the column named in `userKey` (user). An object is an active row:
   * only a row whose `disabledAt` is null and whose `status` is in `active`
   * is active, and a missing row counts as disabled. Disabled tenants and
   * users get no permissions. Under the `provider` model both default to the
   * provider's `suspension`.
   */
  readonly disabled?: {
    readonly tenant?: string | DisabledRow;
    readonly user?: string | DisabledRow;
    readonly userKey?: string;
  };
  readonly activeTenant?: ActiveTenantSource;
}

/**
 * `blocks` in the config, keyed by module name. Each block's `options` is
 * typed from its manifest's options schema, and a name that is no SQL
 * module is a type error.
 */
export type BlocksConfig = {
  readonly [M in keyof BlockOptionsRegistry]?: M extends "access"
    ? AccessBlockConfig<BlockOptionsRegistry[M]>
    : BlockConfig<BlockOptionsRegistry[M]>;
};

/** `blocks` keyed by any module name, as the resolved config and the SQL renderer read it. */
export interface AnyBlocksConfig {
  readonly access?: AccessBlockConfig;
  /** `AccessBlockConfig` is listed so an `access` entry fits the index signature. */
  readonly [module: string]: BlockConfig | AccessBlockConfig | undefined;
}

/** A module's config with defaults applied. */
export interface ResolvedModule {
  readonly mode: BlockMode;
  readonly schema: string;
  readonly tables: Readonly<Record<string, string | null>>;
  readonly columns: Readonly<
    Record<string, Readonly<Record<string, string | null>>>
  >;
  readonly idType?: string;
  readonly permissions: Readonly<Record<string, string>>;
  readonly options: Readonly<Record<string, unknown>>;
  readonly hooks: {
    readonly schema: string;
    readonly functions: Readonly<Record<string, string>>;
  };
  readonly events: boolean;
  readonly audit: boolean;
  readonly api?: {
    readonly schema: string;
    readonly functions?: readonly string[];
  };
}

const MODULE_SCHEMA = "better_supabase";

export function resolveModule(config: BlockConfig = {}): ResolvedModule {
  return {
    mode: config.mode ?? "managed",
    schema: config.schema ?? MODULE_SCHEMA,
    tables: config.tables ?? {},
    columns: config.columns ?? {},
    ...(config.idType === undefined ? {} : { idType: config.idType }),
    permissions: config.permissions ?? {},
    options: config.options ?? {},
    hooks: {
      schema: config.hooks?.schema ?? "public",
      functions: config.hooks?.functions ?? {},
    },
    events: config.events ?? true,
    audit: config.audit ?? true,
    ...(config.api === undefined || config.api === false
      ? {}
      : {
          api:
            typeof config.api === "string"
              ? { schema: config.api }
              : config.api,
        }),
  };
}
