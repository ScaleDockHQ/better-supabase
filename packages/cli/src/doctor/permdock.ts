import type { KitPermdock } from "better-supabase/sql";

import { permdockKeys } from "better-supabase/sql";

import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { entitlementHelpers, entitlementsMode } from "../permdock.ts";
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
      "PermDock's SQL helpers (`permitted_<scope>_ids`, `permdock_has`) check role and scope, not row conditions. A bucket or topic policy that names a permission whose catalog entry has `rowConditions: true` grants every object or topic in the scope. Use PermDock's generated policies for those permissions.",
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
      const rowConditions = project.rowConditions;
      if (!rowConditions) {
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
      const fix =
        "Use the policies `permdock rls generate` writes for it, or a permission whose catalog entry has rowConditions: false.";
      for (const { bucket, keys } of fromConfig) {
        for (const key of keys.filter((candidate) =>
          rowConditions.has(candidate),
        )) {
          findings.push({
            message: `buckets.${bucket} uses PermDock permission "${key}", which has row conditions in ${project.catalogPath}. The bucket policy would grant every object in the scope. ${fix}`,
            target: `buckets.${bucket}:${key}`,
          });
        }
      }
      for (const policy of fromSql) {
        for (const key of policy.keys.filter((candidate) =>
          rowConditions.has(candidate),
        )) {
          findings.push({
            message: `Policy "${policy.name}" on ${policy.table} passes "${key}" to PermDock's helpers, but it has row conditions in ${project.catalogPath}. ${fix}`,
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
      "With a PermDock manifest, the `entitlements` kit module reads memberships from PermDock's `member_<scope>_ids()` (in `has_entitlement`) and `member_<scope>_ids_for(uuid)` (in `feature_claims`). Doctor warns when `entitlements.permdock.scope` is not one of the manifest's scopes, when the manifest's `rls.helpers` lacks a helper (run `permdock rls generate` with a current PermDock), or when the snapshot lacks it (apply the migration it wrote).",
    check: (context) => {
      if (!context.config.sql.kit.includes("entitlements")) return [];
      const mode = entitlementsMode(context.config, context.permdock);
      if (mode.kind === "tenant") return [];
      const manifest = context.config.permdock.manifest;
      if (mode.kind === "invalid")
        return [{ message: mode.problem, target: "entitlements.permdock" }];
      const listed = new Set(
        (context.permdock?.manifest?.rls?.helpers ?? []).map(
          (helper) => `${mode.permdock.schema}.${helper.name}`,
        ),
      );
      const read = context.snapshot.schemas.includes(mode.permdock.schema);
      const present = new Set(
        catalogOf(context).functions.map((fn) => `${fn.schema}.${fn.name}`),
      );
      return entitlementHelpers(mode.permdock).flatMap(
        (helper): FindingInput[] => {
          if (!listed.has(helper))
            return [
              {
                message: `${manifest} lists no ${helper}, which the entitlements module calls. Run \`permdock rls generate\` (PermDock writes member_<scope>_ids and member_<scope>_ids_for for every scope), then \`permdock supabase inspect --out\`.`,
                target: helper,
              },
            ];
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
