import type {
  AuthorizationFunctions,
  AuthorizationMembership,
  AuthorizationProvider,
  ResolvedConfig,
} from "../config/index.ts";
import type {
  BlockSqlAccessProvider,
  BlockSqlEntitlementsProvider,
  BlockSqlIdType,
  BlockSqlPermissionKey,
} from "../sql/index.ts";

import { DEFAULT_CLAIMS, splitPermissionLevel } from "../config/index.ts";
import {
  moduleIdType,
  scopeProblems,
  templateFunctions,
} from "../sql/index.ts";

/** The claim a hook sets when `team_ids` is not the user's whole list. */
const TEAM_IDS_TRUNCATED_CLAIM = "team_ids_truncated";

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

/** How findings name the provider. */
export const providerLabel = (provider: AuthorizationProvider): string =>
  `the authorization provider (${provider.name})`;

/** How the `entitlements` SQL module finds memberships. */
export type EntitlementsMode =
  | { readonly kind: "tenant" }
  | {
      readonly kind: "provider";
      readonly provider: BlockSqlEntitlementsProvider;
    }
  | { readonly kind: "invalid"; readonly problem: string };

/** How the `access` module's `provider` model reaches the provider. */
export type AccessProviderMode =
  | { readonly kind: "off" }
  | { readonly kind: "provider"; readonly access: BlockSqlAccessProvider }
  | { readonly kind: "invalid"; readonly problem: string };

type TenantScope =
  | {
      readonly kind: "ok";
      readonly scope: string;
      readonly idType: BlockSqlIdType;
    }
  | { readonly kind: "invalid"; readonly problem: string };

/**
 * The provider's tenant scope and its id type. A scope missing from `scopes`,
 * or without an id type this release renders, is invalid rather than a guess.
 */
function tenantScope(provider: AuthorizationProvider): TenantScope {
  const scope = provider.tenantScope;

  const declared = provider.scopes.find(
    (candidate) => candidate.name === scope,
  )?.idType;

  const idType = declared === undefined ? undefined : moduleIdType(declared);

  const problems = scopeProblems(provider);

  // scopeProblems names a missing tenant scope, its missing idType and an id
  // type outside SCOPE_ID_TYPES, the types moduleIdType reads.
  if (problems.length > 0 || idType === undefined) {
    return {
      kind: "invalid",
      problem: `The scopes of ${providerLabel(provider)} are inconsistent: ${problems.join("; ")}.`,
    };
  }

  return { kind: "ok", scope, idType };
}

/** The provider's membership tables that can hold rows of `scope`. */
const scopeMemberships = (
  provider: AuthorizationProvider,
  scope: string,
): readonly AuthorizationMembership[] =>
  (provider.memberships ?? []).filter(
    (source) => !("value" in source.scope) || source.scope.value === scope,
  );

const quotedName = (name: string): string => `"${name.replaceAll('"', '""')}"`;

const quotedTableName = (table: string): string =>
  table.split(".").map(quotedName).join(".");

/**
 * The `memberIds` and `memberIdsFor` templates a provider's membership rows
 * imply.
 */
function membershipTemplates(
  memberships: readonly AuthorizationMembership[],
): Pick<AuthorizationFunctions, "memberIds" | "memberIdsFor"> | undefined {
  if (memberships.length === 0) {
    return undefined;
  }

  const select = (user: string): string =>
    memberships
      .map((source) => {
        const live =
          source.disabledAt === undefined
            ? ""
            : ` and m.${quotedName(source.disabledAt)} is null`;

        const kind =
          "column" in source.scope
            ? ` and m.${quotedName(source.scope.column)} = '{scope}'`
            : "";

        return `select m.${quotedName(source.idColumn)} as id from ${quotedTableName(source.table)} m where m.${quotedName(source.userKey ?? source.userColumn)} = ${user}${kind}${live}`;
      })
      .join(" union ");

  return {
    memberIds: `(${select("(select auth.uid())")})`,
    memberIdsFor: `(${select("{user}")})`,
  };
}

/**
 * The provider's functions, with `memberIds` and `memberIdsFor` read off its
 * membership rows when it sets the rows and leaves the templates out. A
 * template the provider sets always wins.
 */
function providerFunctions(
  provider: AuthorizationProvider,
  scope: string,
): AuthorizationFunctions {
  const { memberIds, memberIdsFor } = provider.functions;

  if (memberIds !== undefined && memberIdsFor !== undefined) {
    return provider.functions;
  }

  const derived = membershipTemplates(scopeMemberships(provider, scope));

  return derived === undefined
    ? provider.functions
    : {
        ...provider.functions,
        ...(memberIds === undefined && derived.memberIds !== undefined
          ? { memberIds: derived.memberIds }
          : {}),
        ...(memberIdsFor === undefined && derived.memberIdsFor !== undefined
          ? { memberIdsFor: derived.memberIdsFor }
          : {}),
      };
}

/**
 * Provider mode when `entitlements.memberships` resolves to `"provider"` (the
 * default with `authorization`). The provider needs `memberIds` and
 * `memberIdsFor`, so the module never falls back to `tenant` on its own.
 */
export function entitlementsMode(
  config: Pick<ResolvedConfig, "entitlements" | "authorization">,
): EntitlementsMode {
  if (config.entitlements.memberships === "tenant") {
    return { kind: "tenant" };
  }

  const provider = config.authorization;

  if (!provider) {
    return {
      kind: "invalid",
      problem:
        'auth.entitlements.memberships is "provider", but the config has no authorization. Set authorization, or set auth.entitlements.memberships to "tenant".',
    };
  }

  const chosen = tenantScope(provider);

  if (chosen.kind === "invalid") {
    return chosen;
  }

  const { memberIds, memberIdsFor } = providerFunctions(provider, chosen.scope);

  if (memberIds === undefined || memberIdsFor === undefined) {
    return {
      kind: "invalid",
      problem: `${providerLabel(provider)} has no authorization.functions.${memberIds === undefined ? "memberIds" : "memberIdsFor"} and no authorization.memberships for the tenant scope to derive it from, and the entitlements module calls it. Use a provider that sets either, or set auth.entitlements.memberships to "tenant" to keep the tenant module's memberships.`,
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
  config: Pick<ResolvedConfig, "authorization" | "blocks"> &
    Partial<Pick<ResolvedConfig, "claims">>,
): AccessProviderMode {
  const access = config.blocks.permissions;

  if (access?.model !== "provider") {
    return { kind: "off" };
  }

  const provider = config.authorization;

  if (!provider) {
    return {
      kind: "invalid",
      problem:
        'blocks.permissions.model is "provider", but the config has no authorization. Set authorization, or choose another blocks.permissions.model.',
    };
  }

  const chosen = tenantScope(provider);

  if (chosen.kind === "invalid") {
    return chosen;
  }

  const idType =
    access.idType === undefined ? undefined : moduleIdType(access.idType);

  if (idType !== undefined && idType !== chosen.idType) {
    return {
      kind: "invalid",
      problem: `blocks.permissions.idType is "${access.idType}", but ${providerLabel(provider)} gives scope "${chosen.scope}" the type ${chosen.idType}. Set blocks.permissions.idType to "${chosen.idType}", or remove it.`,
    };
  }

  const { user, tenant, userKey } = provider.suspension ?? {};
  const truncatedClaim = providerTruncatedClaim(provider);

  return {
    kind: "provider",
    access: {
      name: provider.name,
      scope: chosen.scope,
      scopes: provider.scopes.map((scope) => scope.name),
      idType: chosen.idType,
      functions: providerFunctions(provider, chosen.scope),
      ...(user || tenant
        ? {
            suspension: {
              ...(user ? { user } : {}),
              ...(tenant ? { tenant } : {}),
              ...(userKey === undefined ? {} : { userKey }),
            },
          }
        : {}),
      ...(provider.roleSources && provider.roleSources.length > 0
        ? { roleSources: provider.roleSources }
        : {}),
      ...(provider.platformRoles
        ? { platformRoles: provider.platformRoles }
        : {}),
      ...(provider.memberships && provider.memberships.length > 0
        ? { memberships: provider.memberships }
        : {}),
      ...(provider.operations && Object.keys(provider.operations).length > 0
        ? { operations: provider.operations }
        : {}),
      sqlCompleteKeys: sqlCompleteKeys(provider),
      ...(provider.tokenHook === undefined
        ? {}
        : { tokenHook: { function: provider.tokenHook.function } }),
      ...(ownsPermissionsClaim(provider, config.claims?.permissions)
        ? { ownsPermissions: true }
        : {}),
      ...(truncatedClaim === undefined ? {} : { truncatedClaim }),
      ...(provider.tokenHook?.teamIdsTruncatedClaim === undefined
        ? {}
        : { teamIdsTruncatedClaim: provider.tokenHook.teamIdsTruncatedClaim }),
      ...(provider.wildcards === undefined
        ? {}
        : { wildcards: provider.wildcards }),
    },
  };
}

/**
 * Whether the provider's hook writes the `permissions` claim (`claim`, as
 * `config.claims.permissions`) itself.
 */
function ownsPermissionsClaim(
  provider: Pick<AuthorizationProvider, "tokenHook">,
  claim: string = DEFAULT_CLAIMS.permissions,
): boolean {
  return provider.tokenHook?.ownedClaims.includes(claim) ?? false;
}

/** What `authorization.permissions` says about a key. */
export type KeyStatus = "complete" | "incomplete" | "unknown" | "missing";

/**
 * `complete` when the provider marks the key `sqlComplete: true`. A key without
 * the flag is unknown, and so is every key when the provider lists no
 * permissions.
 */
export function keyStatus(
  provider: AuthorizationProvider,
  key: string,
): KeyStatus {
  if (!provider.permissions) {
    return "unknown";
  }

  const entry = provider.permissions.find(
    (permission) => permission.key === key,
  );

  if (!entry) {
    // A level key (`file.read@team`) names one level of a listed permission.
    // The tenant-level SQL functions answer for the whole tenant, so a level
    // key is never complete; a level the entry doesn't list is missing.
    const { permission, level } = splitPermissionLevel(key);
    const base = provider.permissions.find((entry) => entry.key === permission);

    return level !== null && base?.levels?.includes(level) === true
      ? "incomplete"
      : "missing";
  }

  if (entry.sqlComplete === undefined) {
    return "unknown";
  }

  return entry.sqlComplete ? "complete" : "incomplete";
}

const INCOMPLETE_FIX =
  "Use the provider's own policies for it, or a permission its SQL functions answer for completely.";

const UNKNOWN_FIX =
  "Have the provider set sqlComplete on every entry of authorization.permissions.";

/**
 * Why the provider's SQL functions can't be trusted with `key`, or `undefined`
 * when it is marked `sqlComplete: true`. Unknown and missing keys count as
 * unsafe.
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
    case "complete": {
      return undefined;
    }

    case "incomplete": {
      return {
        status,
        reason: `has conditions ${providerLabel(provider)}'s SQL functions don't check (sqlComplete: false)`,
        fix: INCOMPLETE_FIX,
      };
    }

    case "unknown": {
      return {
        status,
        reason: provider.permissions
          ? "has no sqlComplete flag in authorization.permissions, so whether the SQL functions answer for it completely is unknown"
          : "can't be checked: authorization.permissions is not set, so whether the SQL functions answer for it completely is unknown",
        fix: UNKNOWN_FIX,
      };
    }

    case "missing": {
      return {
        status,
        reason: "is not in authorization.permissions",
        fix: UNKNOWN_FIX,
      };
    }

    default: {
      const unreachable: never = status;

      return unreachable;
    }
  }
}

/** A module permission key the provider's functions can't answer for fully. */
export interface BlockSqlKeyProblem {
  /** `blocks.<module>.permissions.<action>`, or `authorization.permissions`. */
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
  keys: readonly BlockSqlPermissionKey[],
): BlockSqlKeyProblem[] {
  if (keys.length === 0) {
    return [];
  }

  if (!provider.permissions) {
    return [
      {
        target: "authorization.permissions",
        message: `The provider access model passes ${keys.length} module permission keys to ${providerLabel(provider)}'s SQL functions, but authorization.permissions is not set, so whether they answer for them completely is unknown. Use a provider that lists its permissions.`,
      },
    ];
  }

  return keys.flatMap((entry): BlockSqlKeyProblem[] => {
    const problem = unsafeKey(provider, entry.key);

    if (!problem) {
      return [];
    }

    const fn =
      entry.scope === "platform"
        ? "authorization.functions.isPlatform"
        : "authorization.functions.idsWith";

    const setting =
      entry.setting ?? `blocks.${entry.module}.permissions.${entry.action}`;

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

/** A permission key a config setting, tag or operation hands to the provider. */
export interface CatalogKeyUse {
  readonly key: string;
  /** The setting that names it, such as `authorization.operations.x.permission`. */
  readonly target: string;
  /** What checks it, such as `The mcp.tool.search operation`. */
  readonly checker: string;
}

/**
 * The module key check for keys that do not come from a block: operations,
 * `actionKeys` for buckets and topics, and `@bsb access` tags. Same statuses,
 * same wording: only `sqlComplete: true` passes.
 */
export function catalogKeyProblems(
  provider: AuthorizationProvider,
  uses: readonly CatalogKeyUse[],
): BlockSqlKeyProblem[] {
  if (!provider.permissions) {
    return [];
  }

  return uses.flatMap((use): BlockSqlKeyProblem[] => {
    const problem = unsafeKey(provider, use.key);

    if (!problem) {
      return [];
    }

    const fix =
      problem.status === "incomplete"
        ? `The provider's SQL functions check role and scope, not the key's other conditions, so it would grant everywhere in the scope. Set ${use.target} to a permission marked sqlComplete: true.`
        : `${problem.fix} If the provider doesn't define it, set ${use.target} to a key it lists.`;

    return [
      {
        target: use.target,
        message: `${use.checker} checks "${use.key}" with ${providerLabel(provider)}'s SQL functions, but it ${problem.reason}. ${fix}`,
      },
    ];
  });
}

/** The `@bsb access` tag's key check for `provider`, or none without one. */
export function tagKeyProblem(
  provider: AuthorizationProvider | undefined,
): ((key: string) => string | undefined) | undefined {
  if (provider?.permissions === undefined) {
    return undefined;
  }

  return (key) =>
    catalogKeyProblems(provider, [
      { key, target: "the @bsb access tag", checker: "The @bsb access tag" },
    ])[0]?.message;
}

/**
 * The keys `operations` and `actionKeys` (buckets, topics) hand to the
 * provider.
 */
export function providerKeyUses(
  provider: AuthorizationProvider,
): CatalogKeyUse[] {
  const operations = Object.entries(provider.operations ?? {}).map(
    ([name, operation]): CatalogKeyUse => ({
      key: operation.permission,
      target: `authorization.operations.${name}.permission`,
      checker: `The ${name} operation`,
    }),
  );

  const keys = provider.actionKeys;

  const groups = [
    ["buckets", keys?.buckets],
    ["topics", keys?.topics],
  ] as const;

  const mapped = groups.flatMap(([group, entries]) =>
    Object.entries(entries ?? {}).flatMap(([name, actions]) =>
      Object.entries(actions).map(([action, key]): CatalogKeyUse => ({
        key,
        target: `authorization.actionKeys.${group}.${name}.${action}`,
        checker: `The ${name} ${group === "buckets" ? "bucket" : "topic"} (${action})`,
      })),
    ),
  );

  return [...operations, ...mapped];
}

/**
 * A function a provider template calls (`schema.name`), the template and the
 * role it runs as.
 */
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
  access: BlockSqlAccessProvider,
): readonly ProviderRequirement[] =>
  requirementsOf(access.functions, access.scope, [
    ["idsWith", "authenticated"],
    ["isPlatform", "authenticated"],
  ]);

/**
 * A function the `entitlements` module calls, with the module function that
 * calls it.
 */
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
  provider: BlockSqlEntitlementsProvider,
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

/**
 * The truncated marker the provider's hook sets on the `permissions` claim:
 * `tokenHook.truncatedClaim`, then `budget.truncatedClaim`. `undefined` means
 * the default, `<claim>_truncated`.
 */
export function providerTruncatedClaim(
  provider: Pick<AuthorizationProvider, "tokenHook"> | undefined,
): string | undefined {
  const hook = provider?.tokenHook;

  return hook?.truncatedClaim ?? hook?.budget?.truncatedClaim;
}

/** The truncated markers codegen records when they are not the defaults. */
export function claimMarkerOverrides(
  config: Pick<ResolvedConfig, "authorization" | "blocks">,
): {
  readonly permissionsTruncated?: string;
  readonly teamIdsTruncated?: string;
} {
  const permissionsTruncated = providerTruncatedClaim(config.authorization);
  const teamIdsTruncated = teamIdsTruncatedClaimOf(config);

  return {
    ...(permissionsTruncated === undefined ? {} : { permissionsTruncated }),
    ...(teamIdsTruncated === undefined ? {} : { teamIdsTruncated }),
  };
}

/**
 * The claim that marks a partial `team_ids` list, when it is not the default.
 * The sessions hook option wins, then the provider's
 * `tokenHook.teamIdsTruncatedClaim`.
 */
function teamIdsTruncatedClaimOf(
  config: Pick<ResolvedConfig, "authorization" | "blocks">,
): string | undefined {
  const hook = config.blocks["sessions"]?.options?.["hook"];

  const fromHook =
    isRecord(hook) && typeof hook["teamIdsTruncatedClaim"] === "string"
      ? hook["teamIdsTruncatedClaim"]
      : undefined;

  const claim =
    fromHook ?? config.authorization?.tokenHook?.teamIdsTruncatedClaim;

  return claim === undefined || claim === TEAM_IDS_TRUNCATED_CLAIM
    ? undefined
    : claim;
}

/**
 * The keys the provider marks `sqlComplete: true`: the only ones the SQL
 * functions answer for, and so the only ones the `permissions` claim carries.
 */
export function sqlCompleteKeys(
  provider: Pick<AuthorizationProvider, "permissions">,
): readonly string[] {
  return (provider.permissions ?? [])
    .filter((permission) => permission.sqlComplete === true)
    .map((permission) => permission.key);
}
