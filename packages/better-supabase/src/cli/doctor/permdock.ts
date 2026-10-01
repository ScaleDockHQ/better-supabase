import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { permdockKeys } from "../../core/permdock-sql.ts";

/** Tables whose policies PermDock's helpers can't row-check (PermDock's PD037 scans the same ones). */
const HELPER_TABLES = new Set(["storage.objects", "realtime.messages"]);

const POLICY =
  /create\s+policy\s+("(?:[^"]|"")+"|[\w$]+)\s+on\s+((?:"[^"]+"|\w+)\s*\.\s*(?:"[^"]+"|\w+))([\s\S]*?);/gi;
const HELPER_KEY =
  /\b(?:permitted_\w+_ids|permdock_has)"?\s*\(\s*'((?:[^']|'')*)'/g;

const unquote = (name: string): string =>
  name.replace(/^"|"$/g, "").replaceAll('""', '"');

export interface HelperPolicy {
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
export function helperPolicies(files: readonly TextFile[]): HelperPolicy[] {
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
];
