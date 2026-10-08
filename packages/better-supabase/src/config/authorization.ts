import type { DisabledRow } from "./modules.ts";

/**
 * SQL expression templates the SQL modules and the access policies call.
 * `{permission}` is a text expression (a literal or a parameter), `{user}` a
 * uuid expression, `{tenant}` an expression of the tenant id type and
 * `{role}` a text expression. `{scope}` is the scope's name unquoted, so it
 * can be part of a function name (`app.ids_{scope}({permission})`); write
 * `'{scope}'` to pass it as text.
 */
export interface AuthorizationFunctions {
  /**
   * The ids of the `{scope}` instances where the caller holds
   * `{permission}`, as a set: it is used as
   * `select t.id::text from <template> as t(id)`.
   */
  readonly idsWith: string;
  /** Whether the caller holds `{permission}` platform-wide. */
  readonly isPlatform: string;
  /** `idsWith` for `{user}`, so `can_user` answers for another user. */
  readonly idsWithFor?: string;
  /** `isPlatform` for `{user}`. */
  readonly isPlatformFor?: string;
  /** The ids of the `{scope}` instances the caller is a member of, as a set. */
  readonly memberIds?: string;
  /** `memberIds` for `{user}`, which the access token hook calls as `supabase_auth_admin`. */
  readonly memberIdsFor?: string;
  /** Whether the caller may assign `{role}` in `{tenant}`. */
  readonly canAssign?: string;
  /** Whether `{user}` may assign `{role}` in `{tenant}`. */
  readonly canAssignFor?: string;
}

/** One scope the provider decides permissions in, such as `organization`. */
export interface AuthorizationScope {
  /** Lower case letters, digits and `_`, starting with a letter. */
  readonly name: string;
  /** The Postgres type of the scope's ids: `uuid`, `text`, `bigint` or `integer`. */
  readonly idType?: string;
  /** The scope this one sits in; the root scope has none. */
  readonly parent?: string;
}

/** A function the templates call, which must exist and be executable by `role`. */
export interface AuthorizationRequirement {
  /** `schema.name`. */
  readonly function: string;
  /** The argument types, such as `text` or `uuid, text`. */
  readonly args?: string;
  readonly role: string;
}

/** A permission key the provider defines. */
export interface AuthorizationPermission {
  readonly key: string;
  /**
   * `true` when the SQL functions answer for the key completely. A key with
   * row conditions they don't check is `false`, and policies refuse it.
   * Unset means unknown, which counts as `false`.
   */
  readonly sqlComplete?: boolean;
  /** The scopes it can be granted at. */
  readonly scopes?: readonly string[];
}

/** A table of memberships the provider reads. */
export interface AuthorizationMembership {
  /** `schema.table`. */
  readonly table: string;
  readonly userColumn: string;
  /** The scope column, or the scope every row is in. */
  readonly scope: { readonly column: string } | { readonly value: string };
  readonly idColumn: string;
}

/** A membership table whose role column points into a roles table. */
export interface AuthorizationRoleSource {
  /** `schema.table` of the memberships. */
  readonly table: string;
  readonly role: {
    readonly column: string;
    readonly through: {
      /** `schema.table` of the roles. */
      readonly table: string;
      readonly id: string;
      readonly column: string;
    };
  };
}

/** The access token hook the provider generates. */
export interface AuthorizationTokenHook {
  /** `schema.name`. */
  readonly function: string;
  /** The claim it writes the active tenant id to. */
  readonly tenantClaim?: string;
  /** Claims it writes itself, which a second writer would contradict. */
  readonly ownedClaims: readonly string[];
  /** Claims it fills from other functions, such as `features` from `better_supabase.feature_claims`. */
  readonly registeredClaims?: readonly {
    readonly name: string;
    /** `schema.name`. */
    readonly function: string;
  }[];
  /** A byte budget over some claims, which doctor `--as` measures (BS405). */
  readonly budget?: {
    readonly claims: readonly string[];
    readonly bytes: number;
    /** A claim the hook sets to `true` when it dropped entries to stay within the budget. */
    readonly truncatedClaim?: string;
  };
  /** Comment lines the provider's generated files contain, so doctor recognises them. */
  readonly markers?: {
    /** In the file that defines the hook. */
    readonly hook?: string;
    /** In the migration that grants the hook's functions. */
    readonly grants?: string;
  };
  /** The command that writes the hook's grants, for BS404. */
  readonly grantsCommand?: string;
}

/**
 * An authorization system the SQL modules, the policies and doctor delegate
 * to. It is plain data, usually built from the provider's own output files.
 */
export interface AuthorizationProvider {
  readonly apiVersion: 1;
  /** The provider's name, for messages. */
  readonly name: string;
  readonly scopes: readonly AuthorizationScope[];
  /** The scope tenants are. */
  readonly tenantScope: string;
  readonly functions: AuthorizationFunctions;
  readonly requires?: readonly AuthorizationRequirement[];
  readonly permissions?: readonly AuthorizationPermission[];
  readonly memberships?: readonly AuthorizationMembership[];
  /** Rows that say whether a user or a tenant is active. */
  readonly suspension?: {
    readonly user?: DisabledRow;
    readonly tenant?: DisabledRow;
  };
  readonly roleSources?: readonly AuthorizationRoleSource[];
  /** `schema.table.column` of every column that decides access (BS213). */
  readonly decidingColumns?: readonly string[];
  readonly tokenHook?: AuthorizationTokenHook;
  /** What the provider found wrong while building this, for doctor. */
  readonly problems?: readonly string[];
}
