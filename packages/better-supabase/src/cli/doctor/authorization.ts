import type {
  AuthorizationProvider,
  ResolvedConfig,
} from "../../config/index.ts";
import type { ModuleEntitlementsProvider } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { accessKeys } from "../../core/access-sql.ts";
import { modulePermissionKeys, resolveModules } from "../../sql/index.ts";
import {
  accessProviderMode,
  type AccessProviderMode,
  accessRequirements,
  entitlementRequirements,
  entitlementsMode,
  moduleKeyProblems,
  providerLabel,
  type ProviderRequirement,
  unsafeKey,
} from "../authorization.ts";
import { catalogOf } from "./shared.ts";

/** Tables whose generated policies call the provider's functions by role and scope only. */
const POLICY_TABLES = new Set(["storage.objects", "realtime.messages"]);

const POLICY =
  /create\s+policy\s+("(?:[^"]|"")+"|[\w$]+)\s+on\s+((?:"[^"]+"|\w+)\s*\.\s*(?:"[^"]+"|\w+))([\s\S]*?);/gi;

const unquote = (name: string): string =>
  name.replaceAll(/^"|"$/g, "").replaceAll('""', '"');

const escapeRegExp = (text: string): string =>
  text.replaceAll(/[.*+?^${}()|[\]\\]/g, String.raw`\$&`);

/**
 * A pattern for a filled template: `{permission}` captures the key literal
 * (optionally passed by name), `{scope}` captures the scope name, and
 * whitespace may differ.
 */
function templatePattern(template: string): RegExp {
  const source = template
    .split(/(\{\w+\})/)
    .map((part) => {
      if (part === "{permission}")
        return String.raw`(?:\w+\s*=>\s*)?'((?:[^']|'')*)'`;
      if (part === "{scope}") return "([a-z][a-z0-9_]*)";
      if (/^\{\w+\}$/.test(part)) return String.raw`[\s\S]*?`;
      return escapeRegExp(part).replaceAll(/\s+/g, String.raw`\s*`);
    })
    .join("");
  return new RegExp(source, "gi");
}

interface ProviderCall {
  readonly key: string;
  /** `platform` for `isPlatform`. */
  readonly scope: string;
}

/** The keys and scopes a policy body passes to the provider's `idsWith` and `isPlatform`. */
function providerCalls(
  provider: AuthorizationProvider,
  body: string,
): ProviderCall[] {
  const calls: ProviderCall[] = [];
  const { idsWith, isPlatform } = provider.functions;
  const groups = (template: string): readonly string[] =>
    [...template.matchAll(/\{(permission|scope)\}/g)].map((match) => match[1]!);
  const idsGroups = groups(idsWith);
  for (const match of body.matchAll(templatePattern(idsWith))) {
    const key = match[idsGroups.indexOf("permission") + 1];
    if (key === undefined) continue;
    const scopeIndex = idsGroups.indexOf("scope");
    calls.push({
      key: key.replaceAll("''", "'"),
      scope: scopeIndex === -1 ? provider.tenantScope : match[scopeIndex + 1]!,
    });
  }
  const platformGroups = groups(isPlatform);
  for (const match of body.matchAll(templatePattern(isPlatform))) {
    const key = match[platformGroups.indexOf("permission") + 1];
    if (key !== undefined)
      calls.push({ key: key.replaceAll("''", "'"), scope: "platform" });
  }
  return calls;
}

interface ProviderPolicy {
  readonly name: string;
  readonly table: string;
  readonly calls: readonly ProviderCall[];
  readonly file: string;
  readonly line: number;
}

/**
 * Policies better-supabase generates (`bs_` names) on `storage.objects` and
 * `realtime.messages` that call the provider's templates, with the keys
 * they pass. The first file that declares a policy wins, matching the
 * `sqlFiles` order (declarative schemas, then the newest migration).
 */
function providerPolicies(
  provider: AuthorizationProvider,
  files: readonly TextFile[],
): ProviderPolicy[] {
  const seen = new Set<string>();
  const found: ProviderPolicy[] = [];
  for (const file of files) {
    for (const match of file.text.matchAll(POLICY)) {
      const name = unquote(match[1]!);
      const table = match[2]!
        .split(".")
        .map((part) => unquote(part.trim()))
        .join(".");
      if (!POLICY_TABLES.has(table) || !name.startsWith("bs_")) continue;
      const id = `${table}.${name}`;
      if (seen.has(id)) continue;
      seen.add(id);
      const calls = providerCalls(provider, match[3]!);
      if (calls.length === 0) continue;
      found.push({
        name,
        table,
        calls,
        file: file.path,
        line: file.text.slice(0, match.index).split("\n").length,
      });
    }
  }
  return found;
}

/**
 * `buckets` entries whose access policy reaches the provider's functions:
 * through `sql` templates, or through the access contract under the
 * `provider` model. Their keys and scope (the tenant scope for `tenant`).
 */
export function providerBucketKeys(
  config: Pick<ResolvedConfig, "buckets" | "authorization" | "sql">,
): {
  readonly bucket: string;
  readonly keys: readonly string[];
  readonly scope: string;
}[] {
  const provider = config.authorization;
  if (!provider) return [];
  const providerModel = config.sql.modules.access?.model === "provider";
  return Object.entries(config.buckets).flatMap(([bucket, entry]) => {
    const policy = entry.policy;
    if (policy === undefined || typeof policy === "string") return [];
    if (policy.sql === undefined && !providerModel) return [];
    const scope = policy.scope ?? "tenant";
    return [
      {
        bucket,
        keys: accessKeys(policy.access),
        scope: scope === "tenant" ? provider.tenantScope : scope,
      },
    ];
  });
}

/**
 * Why a policy's scope can't work with the provider: a scope it doesn't
 * declare, or a key it grants only at other scopes.
 */
function placementProblems(
  provider: AuthorizationProvider,
  call: ProviderCall,
  where: string,
): string[] {
  if (call.scope === "platform") return [];
  const label = providerLabel(provider);
  if (!provider.scopes.some((scope) => scope.name === call.scope)) {
    return [
      `${where} uses scope "${call.scope}", which ${label} doesn't declare. Use one of ${provider.scopes.map((scope) => scope.name).join(", ") || "its scopes"}.`,
    ];
  }
  const declared = provider.permissions?.find(
    (permission) => permission.key === call.key,
  )?.scopes;
  if (!declared || declared.length === 0 || declared.includes(call.scope))
    return [];
  return [
    `${where} checks "${call.key}" at scope "${call.scope}", but ${label} grants it at ${declared.map((scope) => `"${scope}"`).join(", ")}, so its SQL functions never grant it there. Use scope "${declared[0]}".`,
  ];
}

/** The provider's memberships for the `entitlements` SQL module, when that mode is valid. */
export function entitlementsModule(
  context: Pick<DoctorContext, "config">,
): ModuleEntitlementsProvider | undefined {
  const mode = entitlementsMode(context.config);
  return mode.kind === "provider" ? mode.provider : undefined;
}

/** The provider for the `provider` access model, when `sql.modules` installs `access`. */
export function accessModule(
  context: Pick<DoctorContext, "config">,
): AccessProviderMode {
  if (
    !resolveModules(context.config.sql.moduleNames, {}).some(
      (module) => module.name === "access",
    )
  )
    return { kind: "off" };
  return accessProviderMode(context.config);
}

/**
 * Checks a function a template calls against `authorization.requires` and
 * the database: listed, executable by `role`, and present when the
 * snapshot read its schema. `undefined` when it passes.
 */
function requirementProblem(
  context: DoctorContext,
  provider: AuthorizationProvider,
  requirement: Pick<ProviderRequirement, "function" | "role">,
  caller: string,
): { readonly message: string; readonly severity?: "info" } | undefined {
  const label = providerLabel(provider);
  const listed = (provider.requires ?? []).filter(
    (entry) => entry.function === requirement.function,
  );
  if (provider.requires !== undefined && listed.length === 0) {
    return {
      message: `${caller} calls ${requirement.function}, but ${label} doesn't list it in authorization.requires. Use a provider version that lists every function its templates call.`,
    };
  }
  if (
    listed.length > 0 &&
    !listed.some((entry) => entry.role === requirement.role)
  ) {
    return {
      message: `${label} says only ${listed.map((entry) => entry.role).join(", ")} may execute ${requirement.function}, but ${caller} calls it as ${requirement.role}. Grant it execute to ${requirement.role} through the provider.`,
    };
  }
  const schema = requirement.function.slice(
    0,
    requirement.function.indexOf("."),
  );
  if (!context.snapshot.schemas.includes(schema)) return undefined;
  const present = catalogOf(context).functions.some(
    (fn) => `${fn.schema}.${fn.name}` === requirement.function,
  );
  return present
    ? undefined
    : {
        message: `${requirement.function} is not in the database, but ${caller} calls it. Apply the provider's migration before the SQL modules.`,
      };
}

export const AUTHORIZATION_RULES: readonly Rule[] = [
  {
    code: "BS214",
    severity: "error",
    title:
      "Permission the provider's SQL functions don't fully answer in a Storage or Realtime policy",
    description:
      "An access policy on a bucket or topic that reaches the authorization provider's functions (through `sql` templates, or through the access contract under the `provider` model) decides by role and scope only. A permission whose `authorization.permissions` entry isn't `sqlComplete: true` would grant every object or topic in the scope, so it is reported, and so is a key the provider doesn't list or every key when it lists no permissions. A scope the provider doesn't declare, and a key checked at another scope than its entry's `scopes`, are reported too. Doctor reads the keys from `buckets` in the config and from the generated `bs_` policies on `storage.objects` and `realtime.messages`.",
    check: (context) => {
      const provider = context.config.authorization;
      if (!provider) return [];
      const findings: FindingInput[] = [];
      for (const { bucket, keys, scope } of providerBucketKeys(
        context.config,
      )) {
        for (const key of keys) {
          for (const message of placementProblems(
            provider,
            { key, scope },
            `buckets.${bucket} ("${key}")`,
          ))
            findings.push({ message, target: `buckets.${bucket}:${key}` });
          const problem = unsafeKey(provider, key);
          if (!problem) continue;
          findings.push({
            message: `buckets.${bucket} uses "${key}", which ${problem.reason}. The bucket policy could grant every object in the scope. ${problem.fix}`,
            target: `buckets.${bucket}:${key}`,
          });
        }
      }
      for (const policy of providerPolicies(provider, context.sqlFiles ?? [])) {
        const seen = new Set<string>();
        for (const call of policy.calls) {
          for (const message of placementProblems(
            provider,
            call,
            `Policy "${policy.name}" on ${policy.table}`,
          )) {
            if (seen.has(message)) continue;
            seen.add(message);
            findings.push({
              message,
              target: `${policy.table}.${policy.name}:${call.key}`,
              location: { file: policy.file, line: policy.line },
            });
          }
        }
        for (const key of new Set(policy.calls.map((call) => call.key))) {
          const problem = unsafeKey(provider, key);
          if (!problem) continue;
          findings.push({
            message: `Policy "${policy.name}" on ${policy.table} passes "${key}" to the provider's SQL functions, but it ${problem.reason}. ${problem.fix}`,
            target: `${policy.table}.${policy.name}:${key}`,
            location: { file: policy.file, line: policy.line },
          });
        }
      }
      return findings;
    },
  },
  {
    code: "BS408",
    severity: "warning",
    title: "The entitlements module can't read the provider's memberships",
    description:
      "With `entitlements.memberships: 'provider'` (the default with `authorization`), the `entitlements` SQL module reads memberships through the provider's `memberIds` template (in `has_entitlement`, as `authenticated`) and `memberIdsFor` (in `feature_claims`, which the provider's hook calls as `supabase_auth_admin`). Doctor warns when the provider can't back that mode (no tenant scope, an id type the module doesn't render, no `memberIds` or `memberIdsFor`), when its hook doesn't fill `claims.features` from `better_supabase.feature_claims` (unless `entitlements.claim` is `false`), when no membership table covers the tenant scope, and when a function those templates call is missing from `authorization.requires`, not executable by that role, or not in the database.",
    check: (context) => {
      if (!context.config.sql.moduleNames.includes("entitlements")) return [];
      const mode = entitlementsMode(context.config);
      if (mode.kind === "tenant") return [];
      if (mode.kind === "invalid")
        return [{ message: mode.problem, target: "entitlements.memberships" }];
      const provider = context.config.authorization!;
      const label = providerLabel(provider);
      const findings: FindingInput[] = [];
      const features = context.config.claims.features;
      const hook = provider.tokenHook;
      if (hook && context.config.entitlements.claim !== false) {
        const claims = hook.registeredClaims ?? [];
        const featureClaim = claims.find((claim) => claim.name === features);
        if (featureClaim?.function !== "better_supabase.feature_claims") {
          const registered = claims.find(
            (claim) => claim.function === "better_supabase.feature_claims",
          );
          findings.push({
            message: registered
              ? `The hook of ${label} fills the "${registered.name}" claim from better_supabase.feature_claims, but claims.features is "${features}", so hasEntitlement() never finds the plan features. Set claims.features to "${registered.name}".`
              : featureClaim
                ? `The hook of ${label} fills the "${features}" claim from ${featureClaim.function}, not better_supabase.feature_claims, so the claim doesn't carry the entitlements module's features. Point the provider's "${features}" claim at better_supabase.feature_claims.`
                : `The hook of ${label} has no "${features}" claim, so it never writes the plan features hasEntitlement() reads. Have it fill "${features}" from better_supabase.feature_claims, or set \`entitlements.claim: false\` to keep the features out of the token and check them in SQL with has_entitlement.`,
            target: `claims.${features}`,
          });
        }
      }
      const scope = mode.provider.scope;
      if (provider.memberships === undefined) {
        findings.push({
          severity: "info",
          message: `${label} lists no authorization.memberships, so entitlement_members() can't tell which tables hold "${scope}" memberships and plan changes never invalidate sessions.`,
          target: "authorization.memberships",
        });
      } else if (mode.provider.memberships.length === 0) {
        findings.push({
          message: `${label} maps no membership table to scope "${scope}", so entitlement_members() finds no users and plan changes never invalidate sessions. Add a membership table for "${scope}" to the provider.`,
          target: "authorization.memberships",
        });
      }
      for (const requirement of entitlementRequirements(mode.provider)) {
        const problem = requirementProblem(
          context,
          provider,
          requirement,
          requirement.caller,
        );
        if (!problem) continue;
        findings.push({
          ...(requirement.kind === "member-for" &&
          problem.message.includes("may execute")
            ? { severity: "info" as const }
            : {}),
          message: problem.message,
          target: requirement.function,
        });
      }
      return findings;
    },
  },
  {
    code: "BS409",
    severity: "warning",
    title: "The authorization provider and the better-supabase config disagree",
    description:
      "The provider's hook writes the active tenant to `tokenHook.tenantClaim`, and its tenant scope is `tenantScope`. Doctor warns when `claims.tenant` names another claim (the tenant plugin, guards and RLS would read a claim the hook never writes), notes when `claims.scope` is neither `tenant` nor the provider's tenant scope, and reports the `problems` the provider found while it was built.",
    check: (context) => {
      const provider = context.config.authorization;
      if (!provider) return [];
      const label = providerLabel(provider);
      const findings: FindingInput[] = (provider.problems ?? []).map(
        (problem) => ({
          message: `${label}: ${problem}`,
          target: "authorization",
        }),
      );
      const tenantClaim = provider.tokenHook?.tenantClaim;
      if (
        tenantClaim !== undefined &&
        tenantClaim !== context.config.claims.tenant
      ) {
        findings.push({
          message: `The hook of ${label} writes the active tenant to "${tenantClaim}", but claims.tenant is "${context.config.claims.tenant}". Set claims.tenant to "${tenantClaim}", or change the provider's tenant claim.`,
          target: "claims.tenant",
        });
      }
      const scope = context.config.claims.scope;
      if (scope !== "tenant" && scope !== provider.tenantScope) {
        findings.push({
          severity: "info",
          message: `claims.scope is "${scope}", but the tenant scope of ${label} is "${provider.tenantScope}". The tenant module's membership claims then use another scope than the provider's. Set claims.scope to "${provider.tenantScope}" (or "tenant").`,
          target: "claims.scope",
        });
      }
      return findings;
    },
  },
  {
    code: "BS411",
    severity: "error",
    title: "The provider access model can't use the authorization provider",
    description:
      "With `sql.modules.access.model: 'provider'`, the `access` module fills the provider's `idsWith` template for tenant checks and `isPlatform` for platform checks, at its tenant scope. Doctor reports a config without `authorization`, a tenant scope or id type the module can't render, a function those templates call that `authorization.requires` doesn't list, doesn't let `authenticated` execute or the database lacks, and every module permission key (from `modulePermissionKeys`) the provider doesn't mark `sqlComplete: true`, since its functions are trusted with role and scope only. It warns when neither `sql.modules.access.functions.canAssign` nor the provider's `canAssign` is set, because only the service role then assigns roles.",
    check: (context) => {
      const mode = accessModule(context);
      if (mode.kind === "off") return [];
      if (mode.kind === "invalid")
        return [{ message: mode.problem, target: "authorization" }];
      const provider = context.config.authorization!;
      const findings: FindingInput[] = [];
      for (const requirement of accessRequirements(mode.access)) {
        const problem = requirementProblem(
          context,
          provider,
          requirement,
          "the provider access model (can() and the SQL modules)",
        );
        if (problem)
          findings.push({
            message: problem.message,
            target: requirement.function,
          });
      }
      findings.push(
        ...moduleKeyProblems(
          provider,
          modulePermissionKeys(
            context.config.sql.modules,
            context.config.sql.moduleNames,
          ),
        ),
      );
      const canAssign =
        context.config.sql.modules.access?.functions?.canAssign ??
        provider.functions.canAssign;
      if (
        canAssign === undefined &&
        !context.config.sql.moduleNames.includes("tenant")
      ) {
        findings.push({
          severity: "warning",
          message: `Neither sql.modules.access.functions.canAssign nor ${providerLabel(provider)} sets canAssign, so under the provider model only the service role assigns roles: the memberships guard refuses every membership a member adds or changes. Use a provider that sets authorization.functions.canAssign, or set sql.modules.access.functions.canAssign.`,
          target: "sql.modules.access.functions.canAssign",
        });
      }
      return findings;
    },
  },
];
