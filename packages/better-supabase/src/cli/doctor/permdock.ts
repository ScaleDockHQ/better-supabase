import type { KitPermdock, PermdockCatalog } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import {
  PERMDOCK_SCHEMA,
  permdockKeys,
  permdockKeyStatus,
} from "../../sql/index.ts";
import {
  entitlementRequirements,
  entitlementsMode,
  parseGrantsMarker,
  parseHookMarker,
  type PermdockManifest,
} from "../permdock.ts";
import { catalogOf } from "./shared.ts";

/** Tables whose policies PermDock's helpers can't row-check (PermDock's PD037 scans the same ones). */
const HELPER_TABLES = new Set(["storage.objects", "realtime.messages"]);

const POLICY =
  /create\s+policy\s+("(?:[^"]|"")+"|[\w$]+)\s+on\s+((?:"[^"]+"|\w+)\s*\.\s*(?:"[^"]+"|\w+))([\s\S]*?);/gi;
/** A helper call: optional schema, `permitted_<scope>_ids` or `permdock_has`, and the key, positional or named. */
const HELPER_CALL =
  /(?:(?:"((?:[^"]|"")+)"|([a-z_][\w$]*))\s*\.\s*)?"?(?:permitted_(\w+?)_ids|(permdock_has))"?\s*\(\s*(?:\w+\s*=>\s*)?'((?:[^']|'')*)'/gi;

const unquote = (name: string): string =>
  name.replaceAll(/^"|"$/g, "").replaceAll('""', '"');

interface HelperCall {
  readonly key: string;
  /** `global` for `permdock_has`. */
  readonly scope: string;
  readonly schema?: string;
}

interface HelperPolicy {
  readonly name: string;
  readonly table: string;
  readonly keys: readonly string[];
  readonly calls: readonly HelperCall[];
  readonly file: string;
  readonly line: number;
}

/**
 * Policies better-supabase generates (`bs_` names) on `storage.objects` and
 * `realtime.messages` that call PermDock's helpers, with the keys they pass.
 * The first file that declares a policy wins, matching the `sqlFiles` order
 * (declarative schemas, then the newest migration).
 */
function helperPolicies(files: readonly TextFile[]): HelperPolicy[] {
  const seen = new Set<string>();
  const found: HelperPolicy[] = [];
  for (const file of files) {
    for (const match of file.text.matchAll(POLICY)) {
      const name = unquote(match[1]!);
      const table = match[2]!
        .split(".")
        .map((part) => unquote(part.trim()))
        .join(".");
      if (!HELPER_TABLES.has(table) || !name.startsWith("bs_")) continue;
      const id = `${table}.${name}`;
      if (seen.has(id)) continue;
      seen.add(id);
      const calls = [...match[3]!.matchAll(HELPER_CALL)].map(
        (call): HelperCall => {
          const schema = call[1]?.replaceAll('""', '"') ?? call[2];
          return {
            key: call[5]!.replaceAll("''", "'"),
            scope: call[4] ? "global" : call[3]!,
            ...(schema ? { schema } : {}),
          };
        },
      );
      if (calls.length === 0) continue;
      found.push({
        name,
        table,
        keys: [...new Set(calls.map((call) => call.key))],
        calls,
        file: file.path,
        line: file.text.slice(0, match.index).split("\n").length,
      });
    }
  }
  return found;
}

/** `buckets` entries with a PermDock policy, the keys they name, their scope and helper schema. */
export function configuredPermdockKeys(
  context: Pick<DoctorContext, "config">,
): {
  readonly bucket: string;
  readonly keys: readonly string[];
  readonly scope: string;
  readonly schema: string;
}[] {
  return Object.entries(context.config.buckets).flatMap(([bucket, config]) =>
    config.policy !== undefined && typeof config.policy !== "string"
      ? [
          {
            bucket,
            keys: permdockKeys(config.policy),
            scope: config.policy.scope,
            schema: config.policy.schema ?? PERMDOCK_SCHEMA,
          },
        ]
      : [],
  );
}

/** A scope name or PermDock's alias for it (`tenant` is the first scope, `team` the second), resolved against the manifest. */
export function resolveManifestScope(
  manifest: PermdockManifest | undefined,
  name: string,
): string | undefined {
  const scopes = manifest?.rls?.scopes;
  if (!scopes) return undefined;
  if (scopes.some((scope) => scope.name === name)) return name;
  if (name === "tenant") return scopes[0]?.name;
  if (name === "team") return scopes[1]?.name;
  return undefined;
}

/**
 * Why a policy's helper schema or scope can't work with PermDock's
 * manifest and catalog: a schema other than `rls.schema`, a scope the
 * manifest doesn't declare, or a key the catalog declares at another scope.
 */
function placementProblems(
  project: NonNullable<DoctorContext["permdock"]>,
  catalog: PermdockCatalog,
  call: HelperCall,
  where: string,
): string[] {
  const rls = project.manifest?.rls;
  const problems: string[] = [];
  if (rls && call.schema !== undefined && call.schema !== rls.schema) {
    problems.push(
      `${where} calls PermDock's helpers in schema ${call.schema}, but ${project.manifestPath} puts them in ${rls.schema}. Set schema: '${rls.schema}' on the policy.`,
    );
  }
  if (call.scope === "global") return problems;
  if (rls && !rls.scopes.some((scope) => scope.name === call.scope)) {
    const resolved = resolveManifestScope(project.manifest, call.scope);
    problems.push(
      `${where} uses scope "${call.scope}", which ${project.manifestPath} doesn't declare, so permitted_${call.scope}_ids doesn't exist. ${resolved ? `Use "${resolved}", the scope "${call.scope}" stands for.` : `Use one of ${rls.scopes.map((scope) => scope.name).join(", ") || "its scopes"}.`}`,
    );
    return problems;
  }
  const declared = catalog.permissions.find(
    (permission) => permission.key === call.key,
  )?.scope;
  if (declared === undefined) return problems;
  const resolved = resolveManifestScope(project.manifest, declared) ?? declared;
  if (resolved !== call.scope) {
    problems.push(
      `${where} checks "${call.key}" at scope "${call.scope}", but ${project.catalogPath} declares it at "${resolved}", so PermDock's helpers never grant it there. Use scope "${resolved}".`,
    );
  }
  return problems;
}

const ROW_CONDITIONS_FIX =
  "Use the policies `permdock rls generate` writes for it, or a permission whose catalog entry has rowConditions: false.";
const REGENERATE_FIX =
  "Regenerate it with a current `permdock catalog`, which writes rowConditions for every permission.";

/**
 * Why the SQL helpers can't be trusted with `key`, or `undefined` when the
 * catalog marks it `rowConditions: false`. An entry without the flag and a
 * key the catalog doesn't list are unknown, so they count as unsafe.
 */
export function unsafeKey(
  catalog: PermdockCatalog,
  key: string,
  catalogPath: string,
): { readonly reason: string; readonly fix: string } | undefined {
  const status = permdockKeyStatus(catalog, key);
  switch (status) {
    case "scope-only":
      return undefined;
    case "row-conditions":
      return {
        reason: `has row conditions in ${catalogPath}`,
        fix: ROW_CONDITIONS_FIX,
      };
    case "no-flag":
      return {
        reason: `has no rowConditions flag in ${catalogPath}, so whether it has row conditions is unknown`,
        fix: REGENERATE_FIX,
      };
    case "missing":
      return { reason: `is not in ${catalogPath}`, fix: REGENERATE_FIX };
    default: {
      const unreachable: never = status;
      return unreachable;
    }
  }
}

/** PermDock's helpers for the `entitlements` kit module, when the manifest allows PermDock mode. */
export function entitlementsKit(
  context: Pick<DoctorContext, "config" | "permdock">,
): KitPermdock | undefined {
  const mode = entitlementsMode(context.config, context.permdock);
  return mode.kind === "permdock" ? mode.permdock : undefined;
}

export const PERMDOCK_RULES: readonly Rule[] = [
  {
    code: "BS214",
    severity: "error",
    title:
      "PermDock permission with row conditions in a Storage or Realtime policy",
    description:
      "PermDock's SQL helpers (`permitted_<scope>_ids`, `permdock_has`) check role and scope, not row conditions. A bucket or topic policy that names a permission whose catalog entry has `rowConditions: true` grants every object or topic in the scope. Use PermDock's generated policies for those permissions. A key whose entry has no boolean `rowConditions` (an older `permdock catalog`) or that the catalog doesn't list is unknown and reported the same way, and so are all of them when the catalog is missing or unreadable. With the manifest, a helper schema other than `rls.schema`, a scope the manifest doesn't declare and a key checked at another scope than its catalog entry's are reported too.",
    check: (context) => {
      const project = context.permdock;
      if (!project) return [];
      const fromConfig = configuredPermdockKeys(context);
      const fromSql = helperPolicies(context.sqlFiles ?? []);
      const uses = fromConfig.length > 0 || fromSql.length > 0;
      const findings: FindingInput[] = project.problems
        .filter((problem) => problem.startsWith(project.catalogPath))
        .map((problem) => ({
          ...(uses ? {} : { severity: "info" as const }),
          message: `Could not read PermDock's catalog: ${problem}`,
          target: project.catalogPath,
        }));
      const catalog = project.catalog;
      if (!catalog) {
        if (findings.length === 0 && uses) {
          findings.push({
            message: `Storage or Realtime policies call PermDock's helpers, but there is no ${project.catalogPath}, so whether their permissions have row conditions is unknown. Run \`permdock catalog\`, or set permdock.catalog in the config.`,
            target: project.catalogPath,
          });
        }
        return findings;
      }
      for (const { bucket, keys, scope, schema } of fromConfig) {
        for (const key of keys) {
          for (const message of placementProblems(
            project,
            catalog,
            { key, scope, schema },
            `buckets.${bucket} ("${key}")`,
          ))
            findings.push({ message, target: `buckets.${bucket}:${key}` });
          const problem = unsafeKey(catalog, key, project.catalogPath);
          if (!problem) continue;
          findings.push({
            message: `buckets.${bucket} uses PermDock permission "${key}", which ${problem.reason}. The bucket policy could grant every object in the scope. ${problem.fix}`,
            target: `buckets.${bucket}:${key}`,
          });
        }
      }
      for (const policy of fromSql) {
        const seen = new Set<string>();
        for (const call of policy.calls) {
          for (const message of placementProblems(
            project,
            catalog,
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
        for (const key of policy.keys) {
          const problem = unsafeKey(catalog, key, project.catalogPath);
          if (!problem) continue;
          findings.push({
            message: `Policy "${policy.name}" on ${policy.table} passes "${key}" to PermDock's helpers, but it ${problem.reason}. ${problem.fix}`,
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
    title: "PermDock helpers the entitlements module calls are missing",
    description:
      "With a PermDock manifest, the `entitlements` kit module reads memberships from PermDock's `member_<scope>_ids()` (in `has_entitlement`, as `authenticated`) and `member_<scope>_ids_for(uuid)` (in `feature_claims`, which PermDock's hook calls as `supabase_auth_admin`). Doctor warns when a PermDock project has no readable manifest or no `rls` block, when the scope is not one of the manifest's scopes or can't be chosen, when the scope's id type is missing or not `uuid`, `text`, `bigint` or `integer`, when the manifest has no `claims.features` claim filled by `better_supabase.feature_claims`, when no membership source covers the scope, when the manifest's `rls.helpers` lacks one of those helpers or doesn't grant it to that role (naming the `permdock.config.ts` setting that adds it), or when the snapshot lacks it (apply the migration `permdock rls generate` wrote).",
    check: (context) => {
      if (!context.config.sql.kit.includes("entitlements")) return [];
      const mode = entitlementsMode(context.config, context.permdock);
      if (mode.kind === "tenant") return [];
      const manifest = context.config.permdock.manifest;
      if (mode.kind === "invalid")
        return [{ message: mode.problem, target: "entitlements.permdock" }];
      const listed = new Map(
        (context.permdock?.manifest?.rls?.helpers ?? []).map((helper) => [
          `${mode.permdock.schema}.${helper.name}`,
          helper,
        ]),
      );
      const read = context.snapshot.schemas.includes(mode.permdock.schema);
      const present = new Set(
        catalogOf(context).functions.map((fn) => `${fn.schema}.${fn.name}`),
      );
      const regenerate = `then run \`permdock rls generate\`, \`permdock supabase hook generate\` and \`permdock supabase inspect --out\`.`;
      const findings: FindingInput[] = [];
      const project = context.permdock;
      const features = context.config.claims.features;
      const claims = project?.manifest?.claims ?? [];
      const featureClaim = claims.find((claim) => claim.name === features);
      if (featureClaim?.source !== "better_supabase.feature_claims") {
        const registered = claims.find(
          (claim) => claim.source === "better_supabase.feature_claims",
        );
        findings.push({
          message: registered
            ? `${manifest} registers better_supabase.feature_claims as the "${registered.name}" claim, but claims.features is "${features}", so hasEntitlement() never finds the plan features. Set claims.features to "${registered.name}", or rename the claim in permdock.config.ts (supabase.hook.claims).`
            : featureClaim
              ? `${manifest} fills the "${features}" claim from ${featureClaim.source}, not better_supabase.feature_claims, so the claim doesn't carry the entitlements module's features. Point supabase.hook.claims.${features} in permdock.config.ts at 'better_supabase.feature_claims', ${regenerate}`
              : `${manifest} has no "${features}" claim, so PermDock's hook never writes the plan features hasEntitlement() reads. Add \`supabase.hook.claims: { ${features}: 'better_supabase.feature_claims' }\` to permdock.config.ts, ${regenerate}`,
          target: `claims.${features}`,
        });
      }
      const scope = mode.permdock.scope;
      const covered = mode.permdock.memberships.some(
        (source) => !("value" in source.scope) || source.scope.value === scope,
      );
      if (!covered) {
        findings.push({
          message: `No membership source in ${manifest} covers scope "${scope}", so entitlement_members() finds no users and plan changes never invalidate sessions. Add a source for "${scope}" (\`supabase.hook.memberships\` in permdock.config.ts), ${regenerate}`,
          target: `entitlements.permdock.${scope}`,
        });
      }
      return findings.concat(
        entitlementRequirements(mode.permdock).flatMap(
          (requirement): FindingInput[] => {
            const { helper, caller, role } = requirement;
            const entry = listed.get(helper);
            if (!entry) {
              const message =
                requirement.kind === "member"
                  ? `${manifest} lists no ${helper}, but ${caller} calls it. Run \`permdock rls generate\` with a current PermDock, then \`permdock supabase inspect --out\`.`
                  : `${manifest} lists no ${helper}, but ${caller} calls it. PermDock writes it only for a scope with a membership source: add one for "${mode.permdock.scope}" (\`supabase.hook.memberships\`, \`rls.membershipSources\` or a mapped \`rls.memberships\` table in permdock.config.ts), ${regenerate}`;
              return [{ message, target: helper }];
            }
            if (!entry.execute.includes(role)) {
              const message =
                requirement.kind === "member"
                  ? `${manifest} says ${role} may not execute ${helper}, but ${caller} calls it as ${role}. Run \`permdock rls generate\` with a current PermDock, then \`permdock supabase inspect --out\`.`
                  : `${manifest} says ${role} may not execute ${helper}. feature_claims runs as its owner, so this only matters when something else calls it as ${role}; PermDock grants it when the hook has claims (\`supabase.hook.claims\` in permdock.config.ts), ${regenerate}`;
              return [
                {
                  ...(requirement.kind === "member-for"
                    ? { severity: "info" as const }
                    : {}),
                  message,
                  target: helper,
                },
              ];
            }
            if (read && !present.has(helper))
              return [
                {
                  message: `${helper} is in ${manifest} but not in the database. Apply the migration \`permdock rls generate\` wrote before the entitlements module.`,
                  target: helper,
                },
              ];
            return [];
          },
        ),
      );
    },
  },
  {
    code: "BS409",
    severity: "warning",
    title: "PermDock's manifest and the better-supabase config disagree",
    description:
      "PermDock's hook and helpers read the active tenant from the manifest's `rls.tenantClaim`, and its generated files start with a `-- permdock:hook v1` or `-- permdock:grants v1` marker. Doctor warns when `claims.tenant` names another claim (the tenant plugin, guards and RLS would read a claim PermDock never writes), reports an error for a marker version this release can't read, and notes when `claims.scope` resolves to another scope than the manifest's root scope.",
    check: (context) => {
      const project = context.permdock;
      if (!project) return [];
      const findings: FindingInput[] = [];
      const manifest = project.manifest;
      const tenantClaim = manifest?.rls?.tenantClaim ?? manifest?.tenantClaim;
      if (
        tenantClaim !== undefined &&
        tenantClaim !== context.config.claims.tenant
      ) {
        findings.push({
          message: `${project.manifestPath} says PermDock writes the active tenant to "${tenantClaim}", but claims.tenant is "${context.config.claims.tenant}". Set claims.tenant to "${tenantClaim}", or change rls.tenantClaim in permdock.config.ts.`,
          target: "claims.tenant",
        });
      }
      for (const file of context.sqlFiles ?? []) {
        const markers = [
          ["hook", parseHookMarker(file.text)?.version],
          ["grants", parseGrantsMarker(file.text)?.version],
        ] as const;
        for (const [kind, version] of markers) {
          if (version === undefined || version === 1) continue;
          findings.push({
            severity: "error",
            message: `${file.path} has a \`-- permdock:${kind} v${String(version)}\` marker, but this release reads only v1, so doctor can't trust what it says about PermDock's ${kind === "hook" ? "hook" : "grants"}. Upgrade better-supabase, or regenerate the file with the PermDock version that matches it.`,
            target: file.path,
            location: { file: file.path, line: 1 },
          });
        }
      }
      const root = manifest?.rls?.scopes.find(
        (scope) => scope.within === undefined,
      )?.name;
      const scope = context.config.claims.scope;
      const resolved = resolveManifestScope(manifest, scope);
      if (root !== undefined && resolved !== root) {
        findings.push({
          severity: "info",
          message: `claims.scope is "${scope}", which ${resolved ? `stands for "${resolved}"` : "is not a scope"} in ${project.manifestPath}, whose root scope is "${root}". The tenant module's membership claims then use another scope than PermDock's. Set claims.scope to "${root}" (or "tenant").`,
          target: "claims.scope",
        });
      }
      return findings;
    },
  },
];
