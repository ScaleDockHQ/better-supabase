/**
 * `sql.modules` in `better-supabase.config.ts`: how each SQL module maps onto
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
export type ModuleMode = "managed" | "adopt" | "custom";

/** Options every module takes. */
export interface ModuleConfig {
  readonly mode?: ModuleMode;
  /** Schema of the module's functions and managed tables. Defaults to `better_supabase`. */
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
  /** Module-specific options; each module's docs page lists them. */
  readonly options?: Readonly<Record<string, unknown>>;
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
   * A schema for the Data API, such as `api`: the module writes a
   * `security invoker` wrapper there for each of its functions that `anon`
   * or `authenticated` may execute (or only those in `functions`), so
   * `rpcTransport(supabase, { schema: "api" })` reaches them without
   * exposing the module schema (doctor BS312).
   */
  readonly api?:
    | string
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
 * A table whose row says whether a tenant or a user is active, in the shape
 * of PermDock's `rls.suspension` rows. Needs `disabledAt`, `status` with
 * `active`, or both.
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

export interface AccessModuleConfig extends ModuleConfig {
  /**
   * `roles`: a fixed role list from `roles` (the default). `catalog`: role,
   * permission and override tables (`tables.roles`, `permissions`,
   * `rolePermissions`, `overrides`, `platformAssignments`). `permdock`:
   * PermDock's `permitted_<scope>_ids` and `permdock_has`. `custom`:
   * expression templates in `functions`.
   */
  readonly model?: "roles" | "catalog" | "permdock" | "custom";
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
     * Required by the `custom` model. For the `permdock` model, use
     * PermDock's assignment rule:
     * `'permdock.permdock_can_assign({role}, {tenant}::text)'` (with the
     * manifest's `rls.schema`). Without it, the `permdock` model lets only
     * the service role assign roles: PermDock projects don't install the
     * `tenant` module (doctor BS407), whose owner-role fallback is the only
     * other rule, and doctor BS411 warns.
     */
    readonly canAssign?: string;
    /** `{user}`: the permission claim for the access token hook. */
    readonly permissionClaims?: string;
  };
  /**
   * `roles` model: the JWT claim holding the caller's platform permission
   * keys (an array). Defaults to `platform_permissions`.
   */
  readonly platformClaim?: string;
  /**
   * What disables a tenant or a user. A string is a column that disables
   * when set, as `schema.table.column`, keyed by the table's `id` (tenant)
   * or the column named in `userKey` (user). An object is PermDock's
   * active-row shape (`rls.suspension`): only a row whose `disabledAt` is
   * null and whose `status` is in `active` is active, and a missing row
   * counts as disabled. Disabled tenants and users get no permissions.
   * Under the `permdock` model both default to the manifest's
   * `rls.suspension`.
   */
  readonly disabled?: {
    readonly tenant?: string | DisabledRow;
    readonly user?: string | DisabledRow;
    readonly userKey?: string;
  };
  readonly activeTenant?: ActiveTenantSource;
  /**
   * `permdock` model: PermDock's `rls.schema` and the scope tenants are.
   * `forUser: true` says PermDock's helpers for a named user
   * (`permdock_has_for`, `permitted_<scope>_ids_for`,
   * `permdock_can_assign_for`, from `database` mode) exist when the manifest
   * doesn't list them.
   */
  readonly permdock?: {
    readonly schema?: string;
    readonly scope?: string;
    readonly forUser?: boolean;
  };
}

/** `sql.modules` in the config, keyed by module name. */
export interface ModulesConfig {
  readonly access?: AccessModuleConfig;
  /** `AccessModuleConfig` is listed so an `access` literal passes the excess-property check. */
  readonly [module: string]: ModuleConfig | AccessModuleConfig | undefined;
}

/** A module's config with defaults applied. */
export interface ResolvedModule {
  readonly mode: ModuleMode;
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
  readonly api?: {
    readonly schema: string;
    readonly functions?: readonly string[];
  };
}

const MODULE_SCHEMA = "better_supabase";

export function resolveModule(config: ModuleConfig = {}): ResolvedModule {
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
    ...(config.api === undefined
      ? {}
      : {
          api:
            typeof config.api === "string"
              ? { schema: config.api }
              : config.api,
        }),
  };
}
