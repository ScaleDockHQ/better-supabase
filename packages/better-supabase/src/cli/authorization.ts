import type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationProvider,
  ResolvedConfig,
  ResolvedSqlConfig,
} from "../config/index.ts";
import type {
  ModuleAccessProvider,
  ModuleEntitlementsProvider,
  ModuleIdType,
  ModulePermissionKey,
} from "../sql/index.ts";

import {
  MODULE_ID_TYPES,
  moduleIdType,
  templateFunctions,
} from "../sql/index.ts";

/** How findings name the provider. */
export const providerLabel = (provider: AuthorizationProvider): string =>
  `the authorization provider (${provider.name})`;

/** How the `entitlements` SQL module finds memberships. */
export type EntitlementsMode =
  | { readonly kind: "tenant" }
  | {
      readonly kind: "provider";
      readonly provider: ModuleEntitlementsProvider;
    }
  | { readonly kind: "invalid"; readonly problem: string };

/** How the `access` module's `provider` model reaches the provider. */
export type AccessProviderMode =
  | { readonly kind: "off" }
  | { readonly kind: "provider"; readonly access: ModuleAccessProvider }
  | { readonly kind: "invalid"; readonly problem: string };

type TenantScope =
  | {
      readonly kind: "ok";
      readonly scope: string;
      readonly idType: ModuleIdType;
    }
  | { readonly kind: "invalid"; readonly problem: string };

/**
 * The provider's tenant scope and its id type. A scope missing from
 * `scopes`, or without an id type this release renders, is invalid rather
 * than a guess.
 */
function tenantScope(
  provider: AuthorizationProvider,
  subject: string,
): TenantScope {
  const scope = provider.tenantScope;
  const entry = provider.scopes.find((candidate) => candidate.name === scope);
  const label = providerLabel(provider);
  if (!entry) {
    return {
      kind: "invalid",
      problem: `authorization.tenantScope is "${scope}", but ${label} has the scopes ${provider.scopes.map((candidate) => candidate.name).join(", ") || "none"}.`,
    };
  }
  if (entry.idType === undefined) {
    return {
      kind: "invalid",
      problem: `${label} gives scope "${scope}" no idType, so ${subject} can't tell its id type.`,
    };
  }
  const idType = moduleIdType(entry.idType);
  if (idType === undefined) {
    return {
      kind: "invalid",
      problem: `${label} gives scope "${scope}" the type ${entry.idType}, but ${subject} renders only ${MODULE_ID_TYPES.join(", ").replace(/, (?=[^,]*$)/, " or ")} ids.`,
    };
  }
  return { kind: "ok", scope, idType };
}

/** The provider's membership tables that can hold rows of `scope`. */
export const scopeMemberships = (
  provider: AuthorizationProvider,
  scope: string,
): readonly AuthorizationMembership[] =>
  (provider.memberships ?? []).filter(
    (source) => !("value" in source.scope) || source.scope.value === scope,
  );

/**
 * Provider mode when `entitlements.memberships` resolves to `"provider"`
 * (the default with `authorization`). The provider needs `memberIds` and
 * `memberIdsFor`, so the module never falls back to `tenant` on its own.
 */
export function entitlementsMode(
  config: Pick<ResolvedConfig, "entitlements" | "authorization">,
): EntitlementsMode {
  if (config.entitlements.memberships === "tenant") return { kind: "tenant" };
  const provider = config.authorization;
  if (!provider) {
    return {
      kind: "invalid",
      problem:
        'entitlements.memberships is "provider", but the config has no authorization. Set authorization, or set entitlements.memberships to "tenant".',
    };
  }
  const chosen = tenantScope(provider, "the entitlements module");
  if (chosen.kind === "invalid") return chosen;
  const { memberIds, memberIdsFor } = provider.functions;
  if (memberIds === undefined || memberIdsFor === undefined) {
    return {
      kind: "invalid",
      problem: `${providerLabel(provider)} has no authorization.functions.${memberIds === undefined ? "memberIds" : "memberIdsFor"}, which the entitlements module calls. Use a provider that sets both, or set entitlements.memberships to "tenant" to keep the tenant module's memberships.`,
    };
  }
  return {
    kind: "provider",
    provider: {
      name: provider.name,
      scope: chosen.scope,
      idType: chosen.idType,
      memberIds,
      memberIdsFor,
      memberships: scopeMemberships(provider, chosen.scope),
    },
  };
}

/**
 * The `provider` access model's functions, from `authorization`. `off` when
 * another model is chosen; without a provider the model is invalid, never a
 * default.
 */
export function accessProviderMode(
  config: Pick<ResolvedConfig, "authorization"> & {
    readonly sql: Pick<ResolvedSqlConfig, "modules">;
  },
): AccessProviderMode {
  const access = config.sql.modules.access;
  if (access?.model !== "provider") return { kind: "off" };
  const provider = config.authorization;
  if (!provider) {
    return {
      kind: "invalid",
      problem:
        'sql.modules.access.model is "provider", but the config has no authorization. Set authorization, or choose another sql.modules.access.model.',
    };
  }
  const chosen = tenantScope(provider, "the provider access model");
  if (chosen.kind === "invalid") return chosen;
  const idType =
    access.idType === undefined ? undefined : moduleIdType(access.idType);
  if (idType !== undefined && idType !== chosen.idType) {
    return {
      kind: "invalid",
      problem: `sql.modules.access.idType is "${access.idType}", but ${providerLabel(provider)} gives scope "${chosen.scope}" the type ${chosen.idType}. Set sql.modules.access.idType to "${chosen.idType}", or remove it.`,
    };
  }
  const { user, tenant } = provider.suspension ?? {};
  return {
    kind: "provider",
    access: {
      name: provider.name,
      scope: chosen.scope,
      idType: chosen.idType,
      functions: provider.functions,
      ...(user || tenant
        ? {
            suspension: {
              ...(user ? { user } : {}),
              ...(tenant ? { tenant } : {}),
            },
          }
        : {}),
      ...(provider.roleSources && provider.roleSources.length > 0
        ? { roleSources: provider.roleSources }
        : {}),
    },
  };
}

/** What `authorization.permissions` says about a key. */
export type KeyStatus = "complete" | "incomplete" | "unknown" | "missing";

/**
 * `complete` when the provider marks the key `sqlComplete: true`. A key
 * without the flag is unknown, and so is every key when the provider lists
 * no permissions.
 */
export function keyStatus(
  provider: AuthorizationProvider,
  key: string,
): KeyStatus {
  if (!provider.permissions) return "unknown";
  const entry = provider.permissions.find(
    (permission) => permission.key === key,
  );
  if (!entry) return "missing";
  if (entry.sqlComplete === undefined) return "unknown";
  return entry.sqlComplete ? "complete" : "incomplete";
}

const INCOMPLETE_FIX =
  "Use the provider's own policies for it, or a permission its SQL functions answer for completely.";
const UNKNOWN_FIX =
  "Have the provider set sqlComplete on every entry of authorization.permissions.";

/**
 * Why the provider's SQL functions can't be trusted with `key`, or
 * `undefined` when it is marked `sqlComplete: true`. Unknown and missing
 * keys count as unsafe.
 */
export function unsafeKey(
  provider: AuthorizationProvider,
  key: string,
):
  | {
      readonly status: Exclude<KeyStatus, "complete">;
      readonly reason: string;
      readonly fix: string;
    }
  | undefined {
  const status = keyStatus(provider, key);
  switch (status) {
    case "complete":
      return undefined;
    case "incomplete":
      return {
        status,
        reason: `has conditions ${providerLabel(provider)}'s SQL functions don't check (sqlComplete: false)`,
        fix: INCOMPLETE_FIX,
      };
    case "unknown":
      return {
        status,
        reason: provider.permissions
          ? "has no sqlComplete flag in authorization.permissions, so whether the SQL functions answer for it completely is unknown"
          : "can't be checked: authorization.permissions is not set, so whether the SQL functions answer for it completely is unknown",
        fix: UNKNOWN_FIX,
      };
    case "missing":
      return {
        status,
        reason: "is not in authorization.permissions",
        fix: UNKNOWN_FIX,
      };
    default: {
      const unreachable: never = status;
      return unreachable;
    }
  }
}

/** A module permission key the provider's functions can't answer for fully. */
export interface ModuleKeyProblem {
  /** `sql.modules.<module>.permissions.<action>`, or `authorization.permissions`. */
  readonly target: string;
  readonly message: string;
}

/**
 * Checks the keys the SQL modules pass to the provider's functions against
 * `authorization.permissions`, with the statuses bucket policies use: only
 * `sqlComplete: true` passes.
 */
export function moduleKeyProblems(
  provider: AuthorizationProvider,
  keys: readonly ModulePermissionKey[],
): ModuleKeyProblem[] {
  if (keys.length === 0) return [];
  if (!provider.permissions) {
    return [
      {
        target: "authorization.permissions",
        message: `The provider access model passes ${keys.length} module permission keys to ${providerLabel(provider)}'s SQL functions, but authorization.permissions is not set, so whether they answer for them completely is unknown. Use a provider that lists its permissions.`,
      },
    ];
  }
  return keys.flatMap((entry): ModuleKeyProblem[] => {
    const problem = unsafeKey(provider, entry.key);
    if (!problem) return [];
    const fn =
      entry.scope === "platform"
        ? "authorization.functions.isPlatform"
        : "authorization.functions.idsWith";
    const setting = `sql.modules.${entry.module}.permissions.${entry.action}`;
    const fix =
      problem.status === "incomplete"
        ? `The provider's SQL functions check role and scope, not the key's other conditions, so the module would grant it everywhere in the scope. Set ${setting} to a permission marked sqlComplete: true.`
        : `${problem.fix} If the provider doesn't define it, set ${setting} to a key it lists.`;
    return [
      {
        target: setting,
        message: `The ${entry.module} module checks "${entry.key}" (${entry.action}) with ${fn}, but it ${problem.reason}. ${fix}`,
      },
    ];
  });
}

/** A function a provider template calls (`schema.name`), the template and the role it runs as. */
export interface ProviderRequirement {
  readonly function: string;
  readonly template: keyof AuthorizationFunctions;
  readonly role: "authenticated" | "supabase_auth_admin";
}

const requirementsOf = (
  functions: AuthorizationFunctions,
  scope: string,
  templates: readonly (readonly [
    keyof AuthorizationFunctions,
    ProviderRequirement["role"],
  ])[],
): ProviderRequirement[] =>
  templates.flatMap(([template, role]) => {
    const sql = functions[template];
    return sql === undefined
      ? []
      : templateFunctions(sql, scope).map((fn) => ({
          function: fn,
          template,
          role,
        }));
  });

/** The functions the `provider` access model calls, as `authenticated`. */
export const accessRequirements = (
  access: ModuleAccessProvider,
): readonly ProviderRequirement[] =>
  requirementsOf(access.functions, access.scope, [
    ["idsWith", "authenticated"],
    ["isPlatform", "authenticated"],
  ]);

/** A function the `entitlements` module calls, with the module function that calls it. */
export interface EntitlementRequirement extends ProviderRequirement {
  readonly kind: "member" | "member-for";
  readonly caller: "has_entitlement" | "feature_claims";
}

/**
 * The functions the `entitlements` module calls for the tenant scope:
 * `memberIds` from `has_entitlement` as `authenticated`, and `memberIdsFor`
 * from `feature_claims`, which the access token hook runs as
 * `supabase_auth_admin`.
 */
export const entitlementRequirements = (
  provider: ModuleEntitlementsProvider,
): readonly EntitlementRequirement[] => [
  ...templateFunctions(provider.memberIds, provider.scope).map(
    (fn): EntitlementRequirement => ({
      kind: "member",
      function: fn,
      template: "memberIds",
      caller: "has_entitlement",
      role: "authenticated",
    }),
  ),
  ...templateFunctions(provider.memberIdsFor, provider.scope).map(
    (fn): EntitlementRequirement => ({
      kind: "member-for",
      function: fn,
      template: "memberIdsFor",
      caller: "feature_claims",
      role: "supabase_auth_admin",
    }),
  ),
];
