/**
 * `kits` in `better-supabase.config.ts`: how each SQL kit module maps onto
 * the app's database. A module's contract (the functions other modules and
 * the TypeScript side call) stays the same in every mode; only the tables
 * behind it change.
 */

/**
 * `managed`: the kit owns its tables. `adopt`: the kit writes its functions
 * and views over tables the app already has (`tables` and `columns`), never
 * `create table`. `custom`: the app implements the contract functions itself;
 * the kit writes nothing and doctor checks the signatures (BS307).
 */
export type KitMode = "managed" | "adopt" | "custom";

/** Options every module takes. */
export interface KitModuleConfig {
  readonly mode?: KitMode;
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
  /** Prefix of the triggers the module creates. Defaults to `bs_`. */
  readonly triggerPrefix?: string;
  /**
   * Kit action to permission key, checked through the access contract, e.g.
   * `{ invite: 'organization.members.invite' }`.
   */
  readonly permissions?: Readonly<Record<string, string>>;
  /** Module-specific options; each module's docs page lists them. */
  readonly options?: Readonly<Record<string, unknown>>;
  /**
   * The app's optional `before_*` and `after_*` functions the module calls
   * when they exist, e.g. `after_organization_create(org, user)`. They are
   * looked up in `schema` (default `public`); `functions` maps a hook name
   * to another function, e.g. `{ after_organization_create: 'app.seed_org' }`.
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
}

/** Where the active tenant of a request comes from. */
export type ActiveTenantSource =
  /** The `claims.tenant` claim (the default). */
  | "claim"
  /**
   * A TypeScript resolver (`ServerOptions.tenant`), e.g. from a URL slug. The
   * server sends it as the `x-bs-tenant` header; `current_tenant_id()` only
   * returns it when the caller is a member.
   */
  | "resolver"
  /** A profile column keyed by the user id, e.g. `public.profiles.active_organization_id`. */
  | { readonly profileColumn: string; readonly key?: string };

/**
 * The access contract every kit checks permissions through:
 * `can(scope, id, permission)`, `tenant_ids_with(permission)`,
 * `is_platform(permission)` and `can_user(user, scope, id, permission)`.
 */
export interface AccessKitConfig extends KitModuleConfig {
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
    /** `{tenant}` and `{role}`: whether the caller may assign the role. Defaults to true. */
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
   * Columns that disable a tenant or a user when set, as
   * `schema.table.column`, keyed by the table's `id` (tenant) or the column
   * named in `userKey` (user). Disabled tenants and users get no permissions.
   */
  readonly disabled?: {
    readonly tenant?: string;
    readonly tenantKey?: string;
    readonly user?: string;
    readonly userKey?: string;
  };
  readonly activeTenant?: ActiveTenantSource;
  /** `permdock` model: PermDock's `rls.schema` and the scope tenants are. */
  readonly permdock?: { readonly schema?: string; readonly scope?: string };
}

/** `kits` in the config, keyed by module name. */
export interface KitsConfig {
  readonly access?: AccessKitConfig;
  /** `AccessKitConfig` is listed so an `access` literal passes the excess-property check. */
  readonly [module: string]: KitModuleConfig | AccessKitConfig | undefined;
}

/** A module's config with defaults applied. */
export interface ResolvedKitModule {
  readonly mode: KitMode;
  readonly schema: string;
  readonly tables: Readonly<Record<string, string | null>>;
  readonly columns: Readonly<
    Record<string, Readonly<Record<string, string | null>>>
  >;
  readonly idType?: string;
  readonly triggerPrefix: string;
  readonly permissions: Readonly<Record<string, string>>;
  readonly options: Readonly<Record<string, unknown>>;
  readonly hooks: {
    readonly schema: string;
    readonly functions: Readonly<Record<string, string>>;
  };
  readonly events: boolean;
}

const KIT_SCHEMA = "better_supabase";

export function resolveKitModule(
  config: KitModuleConfig = {},
): ResolvedKitModule {
  return {
    mode: config.mode ?? "managed",
    schema: config.schema ?? KIT_SCHEMA,
    tables: config.tables ?? {},
    columns: config.columns ?? {},
    ...(config.idType === undefined ? {} : { idType: config.idType }),
    triggerPrefix: config.triggerPrefix ?? "bs_",
    permissions: config.permissions ?? {},
    options: config.options ?? {},
    hooks: {
      schema: config.hooks?.schema ?? "public",
      functions: config.hooks?.functions ?? {},
    },
    events: config.events ?? true,
  };
}
