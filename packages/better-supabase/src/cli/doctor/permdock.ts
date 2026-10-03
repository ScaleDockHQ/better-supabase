import type { KitPermdock, PermdockCatalog } from "../../sql/index.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { permdockKeys, permdockKeyStatus } from "../../sql/index.ts";
import { entitlementRequirements, entitlementsMode } from "../permdock.ts";
import { catalogOf } from "./shared.ts";

/** Tables whose policies PermDock's helpers can't row-check (PermDock's PD037 scans the same ones). */
const HELPER_TABLES = new Set(["storage.objects", "realtime.messages"]);

const POLICY =
  /create\s+policy\s+("(?:[^"]|"")+"|[\w$]+)\s+on\s+((?:"[^"]+"|\w+)\s*\.\s*(?:"[^"]+"|\w+))([\s\S]*?);/gi;
const HELPER_KEY =
  /\b(?:permitted_\w+_ids|permdock_has)"?\s*\(\s*'((?:[^']|'')*)'/g;

const unquote = (name: string): string =>
  name.replaceAll(/^"|"$/g, "").replaceAll('""', '"');

interface HelperPolicy {
  readonly name: string;
  readonly table: string;
  readonly keys: readonly string[];
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
      const keys = [...match[3]!.matchAll(HELPER_KEY)].map((key) =>
        key[1]!.replaceAll("''", "'"),
      );
      if (keys.length === 0) continue;
      found.push({
        name,
        table,
        keys: [...new Set(keys)],
        file: file.path,
        line: file.text.slice(0, match.index).split("\n").length,
      });
    }
  }
  return found;
}

/** `buckets` entries with a PermDock policy, and the keys they name. */
export function configuredPermdockKeys(
  context: Pick<DoctorContext, "config">,
): { readonly bucket: string; readonly keys: readonly string[] }[] {
  return Object.entries(context.config.buckets).flatMap(([bucket, config]) =>
    config.policy !== undefined && typeof config.policy !== "string"
      ? [{ bucket, keys: permdockKeys(config.policy) }]
      : [],
  );
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
      "PermDock's SQL helpers (`permitted_<scope>_ids`, `permdock_has`) check role and scope, not row conditions. A bucket or topic policy that names a permission whose catalog entry has `rowConditions: true` grants every object or topic in the scope. Use PermDock's generated policies for those permissions. A key whose entry has no boolean `rowConditions` (an older `permdock catalog`) or that the catalog doesn't list is unknown and reported the same way.",
    check: (context) => {
      const project = context.permdock;
      if (!project) return [];
      const fromConfig = configuredPermdockKeys(context);
      const fromSql = helperPolicies(context.sqlFiles ?? []);
      const findings: FindingInput[] = project.problems
        .filter((problem) => problem.startsWith(project.catalogPath))
        .map((problem) => ({
          severity: "info",
          message: `Could not read PermDock's catalog: ${problem}`,
          target: project.catalogPath,
        }));
      const catalog = project.catalog;
      if (!catalog) {
        if (
          findings.length === 0 &&
          (fromConfig.length > 0 || fromSql.length > 0)
        ) {
          findings.push({
            severity: "info",
            message: `Storage or Realtime policies call PermDock's helpers, but there is no ${project.catalogPath} to check their permissions against. Run \`permdock catalog\`, or set permdock.catalog in the config.`,
            target: project.catalogPath,
          });
        }
        return findings;
      }
      for (const { bucket, keys } of fromConfig) {
        for (const key of keys) {
          const problem = unsafeKey(catalog, key, project.catalogPath);
          if (!problem) continue;
          findings.push({
            message: `buckets.${bucket} uses PermDock permission "${key}", which ${problem.reason}. The bucket policy could grant every object in the scope. ${problem.fix}`,
            target: `buckets.${bucket}:${key}`,
          });
        }
      }
      for (const policy of fromSql) {
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
      "With a PermDock manifest, the `entitlements` kit module reads memberships from PermDock's `member_<scope>_ids()` (in `has_entitlement`, as `authenticated`) and `member_<scope>_ids_for(uuid)` (in `feature_claims`, which PermDock's hook calls as `supabase_auth_admin`). Doctor warns when the scope is not one of the manifest's scopes or can't be chosen, when the scope's id type is missing or not `uuid`, `text` or `bigint`, when the manifest's `rls.helpers` lacks one of those helpers or doesn't grant it to that role (naming the `permdock.config.ts` setting that adds it), or when the snapshot lacks it (apply the migration `permdock rls generate` wrote).",
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
      return entitlementRequirements(mode.permdock).flatMap(
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
                : `${manifest} says ${role} may not execute ${helper}, but ${caller} calls it from PermDock's hook. PermDock grants it only when the hook has claims: add \`supabase.hook.claims: { features: 'better_supabase.feature_claims' }\` to permdock.config.ts, ${regenerate}`;
            return [{ message, target: helper }];
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
      );
    },
  },
];
