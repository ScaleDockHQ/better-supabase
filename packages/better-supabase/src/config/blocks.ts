import type {
  AnyModuleNames,
  BlockSqlNameSet,
  NamesOf,
} from "../blocks/name-registry.ts";
import type { BlockOptionsRegistry } from "../blocks/options-registry.ts";

/**
 * `blocks` in `better-supabase.config.ts`: how each SQL module maps onto the
 * app's database. A module's contract (the functions other modules and the
 * TypeScript side call) stays the same in every mode; only the tables behind it
 * change.
 */

/**
 * `managed`: the module owns its tables. `adopt`: the module writes its
 * functions and views over tables the app already has (`tables` and `columns`),
 * never `create table`. `custom`: the app implements the contract functions
 * itself; the module writes nothing and doctor checks the signatures (BS307).
 */
export type BlockMode = "managed" | "adopt" | "custom";

/**
 * Who a block's rows belong to. `tenant`: a tenant, checked through the access
 * contract (`can`, `tenant_ids_with`). `user`: the signed-in user, whose id the
 * scope column holds. `none`: one shared space every signed-in user reads and
 * writes. Blocks that need tenants run only in `tenant`.
 */
export type BlockScope = "tenant" | "user" | "none";

export const BLOCK_SCOPES: readonly BlockScope[] = ["tenant", "user", "none"];

/**
 * A new name for one of a block's entities: its singular `name`, an irregular
 * plural and, for an entity the block registers as a subject, the URL of one
 * row with `{column}` placeholders.
 */
export interface EntityConfig<Columns extends string = string> {
  /** Defaults to the entity's own name. */
  readonly name?: string;
  /** Defaults to the English plural of `name`. */
  readonly plural?: string;
  /**
   * The page `subject_url` returns, with `{column}` placeholders from the
   * entity's logical columns: `/tasks/{id}`. A list page needs none.
   */
  // `string & {}` keeps a path without placeholders next to the templates.
  readonly url?: `${string}{${Columns}}${string}` | (string & {});
  /** `false` keeps the entity out of `config.records`. */
  readonly subject?: false;
}

/**
 * `blocks.<name>.names`: entity to its new name, e.g. `{ work_item: "task" }`,
 * or the new name of the block's primary entity alone (`"task"`). The module's
 * tables, columns, functions, events, permission keys, hooks and TypeScript
 * names follow.
 */
export type EntitiesConfig<Names extends BlockSqlNameSet = AnyModuleNames> =
  | ([Names["primary"]] extends [never] ? never : string)
  | ([keyof Names["entities"]] extends [never]
      ? never
      : {
          readonly [E in keyof Names["entities"]]?:
            | string
            | EntityConfig<Names["entities"][E]>;
        });

/**
 * Options every module takes; `Options` types `options`
 * (`blocks.<module>.options`) and `Names` the names the other keys accept.
 */
export interface BlockConfig<
  Options extends object = Readonly<Record<string, unknown>>,
  Names extends BlockSqlNameSet = AnyModuleNames,
> {
  readonly mode?: BlockMode;
  /**
   * Schema of the module's functions and managed tables. Defaults to
   * `sql.schema`, then `better_supabase`.
   */
  readonly schema?: string;
  /**
   * Logical table to `table` or `schema.table`, e.g. `{ memberships:
   * 'public.organization_users' }`. An unqualified name is in `schema`. `null`
   * marks an optional table the app doesn't have.
   */
  readonly tables?: {
    readonly [T in keyof Names["tables"]]?: string | null;
  };
  /**
   * Logical table to logical column to column name, e.g. `{ memberships: {
   * tenant: 'organization_id', role: 'role_id' } }`. `null` marks an optional
   * column the adopted table doesn't have.
   */
  readonly columns?: {
    readonly [T in keyof Names["tables"]]?: {
      readonly [C in Names["tables"][T]]?: string | null;
    };
  };
  /** Type of tenant ids: `uuid` (default), `text`, `bigint` or `integer`. */
  readonly idType?: string;
  /** Who the block's rows belong to. Defaults to `sql.scope`, then `tenant`. */
  readonly scope?: BlockScope;
  /**
   * Function name to the name the module writes it under, e.g. `{
   * create_organization: 'start_company' }`. Keys are the default names; an
   * unknown function is an error. `blocks.access.functions` is the custom
   * model's templates instead.
   */
  readonly functions?: { readonly [F in Names["functions"]]?: string };
  /**
   * Module action to permission key, checked through the access contract, e.g.
   * `{ invite: 'organization.members.invite' }`.
   */
  readonly permissions?: { readonly [A in Names["actions"]]?: string };
  /** New names for the block's entities. */
  readonly entities?: EntitiesConfig<Names>;
  /**
   * Module-specific options, typed from the block manifest's options schema;
   * each module's docs page lists them.
   */
  readonly options?: Options;
  /**
   * The app's optional `before_*` and `after_*` functions the module calls when
   * they exist, e.g. `after_organization_create(organization, user)`. They are
   * looked up in `schema` (default `public`); `functions` maps a hook name to
   * another function, e.g. `{ after_organization_create:
   * 'app.seed_organization' }`.
   */
  readonly hooks?: {
    readonly schema?: string;
    readonly functions?: { readonly [H in Names["hooks"]]?: string };
  };
  /**
   * Whether the module writes its events to the outbox (`emit_event`) when the
   * `outbox` module is installed. Defaults to true.
   */
  readonly events?: boolean;
  /**
   * Whether the module writes its actions to the audit log (`audit_event`) when
   * the `audit` module is installed. Defaults to true.
   */
  readonly audit?: boolean;
  /**
   * A schema for the Data API, such as `api`: the module writes a `security
   * invoker` wrapper there for each of its functions that `anon` or
   * `authenticated` may execute (or only those in `functions`), so
   * `rpcTransport(supabase, { schema: "api" })` reaches them without exposing
   * the module schema (doctor BS312). Defaults to `sql.api`; `false` writes no
   * wrappers even when `sql.api` is set.
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
   * default). The server sends it as the `x-bsb-tenant` header, then the
   * `claims.tenant` claim is the fallback.
   */
  | "resolver"
  /**
   * A profile column keyed by the user id, e.g.
   * `public.profiles.active_organization_id`.
   */
  | { readonly profileColumn: string; readonly key?: string };

/**
 * URL tenancy: the tenant comes from the request (a slug), not a stored
 * setting.
 */
export const DEFAULT_ACTIVE_TENANT: ActiveTenantSource = "resolver";

/**
 * The access contract every module checks permissions through: `can(scope, id,
 * permission)`, `tenant_ids_with(permission)`, `is_platform(permission)` and
 * `can_user(user, scope, id, permission)`.
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
  Names extends BlockSqlNameSet = AnyModuleNames,
> extends Omit<BlockConfig<Options, Names>, "functions"> {
  /**
   * `roles`: a fixed role list from `roles` (the default without
   * `authorization`; with it, `provider` is the default). `catalog`: role,
   * permission and override tables (`tables.roles`, `permissions`,
   * `rolePermissions`, `overrides`, `platformAssignments`). `provider`: the
   * functions of the config's `authorization` provider. `custom`: expression
   * templates in `functions`.
   */
  readonly model?: "roles" | "catalog" | "provider" | "custom";
  /**
   * `roles` model: role name to permission keys. `*` grants everything and
   * `prefix.*` a prefix. Defaults to owner, admin, member and viewer.
   */
  readonly roles?: Readonly<Record<string, readonly string[]>>;
  /**
   * `custom` model: SQL expressions with `{scope}`, `{id}`, `{permission}` and
   * `{user}` placeholders, e.g. `{ can:
   * 'public.authorize_scope({scope}::public.scope_type, {id}, {permission})'
   * }`.
   */
  readonly functions?: {
    readonly can?: string;
    readonly tenantIdsWith?: string;
    readonly isPlatform?: string;
    readonly canUser?: string;
    /**
     * `{tenant}` and `{role}`: whether the caller may assign the role. Required
     * by the `custom` model. The `provider` model defaults to the provider's
     * `canAssign`; without either, only the service role assigns roles unless
     * the `tenant` module is installed, and doctor BS411 warns.
     */
    readonly canAssign?: string;
    /**
     * `{user}`, `{tenant}` and `{role}`: whether that user may assign the role,
     * for SQL that acts later for a stored user (an invitation accept checking
     * the inviter again), as `can_assign_as`. The `provider` model defaults to
     * the provider's `canAssignFor`.
     */
    readonly canAssignFor?: string;
    /**
     * `{permission}` and `{tenant}`: the user ids that hold the permission in
     * the tenant, for the `custom` model's notification audiences.
     */
    readonly holdersOf?: string;
    /** `{user}`: the permission claim for the access token hook. */
    readonly permissionClaims?: string;
  };
  /**
   * `roles` model: the JWT claim holding the caller's platform permission keys
   * (an array). Defaults to `platform_permissions`.
   */
  readonly platformClaim?: string;
  /**
   * OAuth scope to the permission keys it grants a delegated token (a
   * `client_id`, or an `act` chain that is not a support or impersonation
   * level). The access functions refuse every key the token's scopes don't map
   * to, whatever the user holds. A scope without an entry grants the key with
   * its own name; map a scope to `["*"]` to grant everything. Merged over
   * `authorization.delegation.scopes`.
   */
  readonly scopes?: Readonly<Record<string, readonly string[]>>;
  /**
   * What disables a tenant or a user. A string is a column that disables when
   * set, as `schema.table.column`, keyed by the table's `id` (tenant) or the
   * column named in `userKey` (user). An object is an active row: only a row
   * whose `disabledAt` is null and whose `status` is in `active` is active, and
   * a missing row counts as disabled. Disabled tenants and users get no
   * permissions. Under the `provider` model both default to the provider's
   * `suspension`.
   */
  readonly disabled?: {
    readonly tenant?: string | DisabledRow;
    readonly user?: string | DisabledRow;
    readonly userKey?: string;
  };
  readonly activeTenant?: ActiveTenantSource;
}

/**
 * `blocks` in the config, keyed by module name. Each block's `options` is typed
 * from its manifest's options schema, and a name that is no SQL module is a
 * type error.
 */
export type BlocksConfig = {
  readonly [M in keyof BlockOptionsRegistry]?: M extends "access"
    ? AccessBlockConfig<BlockOptionsRegistry[M], NamesOf<M>>
    : BlockConfig<BlockOptionsRegistry[M], NamesOf<M>>;
};

/**
 * `blocks` keyed by any module name, as the resolved config and the SQL
 * renderer read it.
 */
export interface AnyBlocksConfig {
  readonly access?: AccessBlockConfig;
  /**
   * `AccessBlockConfig` is listed so an `access` entry fits the index
   * signature.
   */
  readonly [module: string]: BlockConfig | AccessBlockConfig | undefined;
}

/**
 * Block configs built at runtime (a preset, a `/create` design) as the typed
 * `BlocksConfig`. `resolveConfig` checks every module, table, column, function
 * and entity name, so nothing this skips at compile time goes unchecked.
 */
export function asBlocksConfig(blocks: AnyBlocksConfig): BlocksConfig {
  // SAFETY: the config checks in resolveConfig validate every key at runtime.
  return blocks as BlocksConfig;
}

/**
 * The tenant's new singular name (`blocks.tenant.names.organization`), or
 * `undefined` while it is `organization`. `blocks` may be the config's list of
 * block names, which renames nothing.
 */
export function tenantNameOf(
  blocks: AnyBlocksConfig | readonly string[] | undefined,
): string | undefined {
  if (blocks === undefined || isNameList(blocks)) {
    return undefined;
  }

  const entities = blocks["tenant"]?.entities;

  if (entities === undefined || typeof entities === "string") {
    return undefined;
  }

  const value = entities["organization"];

  return typeof value === "string" ? value : value?.name;
}

function isNameList(
  blocks: AnyBlocksConfig | readonly string[],
): blocks is readonly string[] {
  return Array.isArray(blocks);
}

/** A module's config with defaults applied. */
export interface ResolvedBlock {
  readonly mode: BlockMode;
  readonly schema: string;
  readonly tables: Readonly<Record<string, string | null>>;
  readonly columns: Readonly<
    Record<string, Readonly<Record<string, string | null>>>
  >;
  readonly idType?: string;
  readonly scope?: BlockScope;
  readonly functions: Readonly<Record<string, string>>;
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

/** `record` without the keys a typed config leaves `undefined`. */
function defined<V>(
  record: { readonly [key: string]: V | undefined } | undefined,
): Readonly<Record<string, V>> {
  return Object.fromEntries(
    Object.entries(record ?? {}).filter(
      (entry): entry is [string, V] => entry[1] !== undefined,
    ),
  );
}

export function resolveBlock(config: BlockConfig = {}): ResolvedBlock {
  return {
    mode: config.mode ?? "managed",
    schema: config.schema ?? MODULE_SCHEMA,
    tables: defined(config.tables),
    columns: Object.fromEntries(
      Object.entries(defined(config.columns)).map(([table, columns]) => [
        table,
        defined(columns),
      ]),
    ),
    ...(config.idType === undefined ? {} : { idType: config.idType }),
    ...(config.scope === undefined ? {} : { scope: config.scope }),
    functions: defined(config.functions),
    permissions: defined(config.permissions),
    options: config.options ?? {},
    hooks: {
      schema: config.hooks?.schema ?? "public",
      functions: defined(config.hooks?.functions),
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
