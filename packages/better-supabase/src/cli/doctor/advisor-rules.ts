import type { AdvisorCategory, Lint } from "./advisors.ts";
import type {
  DoctorContext,
  FindingInput,
  Rule,
  Severity,
  SqlObject,
} from "./rules.ts";

import { permissiveOverlaps } from "./rls.ts";
import { unindexedForeignKeys } from "./schema-design.ts";
import { exposed } from "./shared.ts";

const ADVISOR_SEVERITY: Record<Lint["level"], Severity> = {
  ERROR: "error",
  WARN: "warning",
  INFO: "info",
};

function lintObject(lint: Lint): SqlObject | undefined {
  const { schema, name, type } = lint.metadata ?? {};
  if (typeof schema !== "string" || typeof name !== "string") return undefined;
  if (type === "table" || type === "view")
    return { kind: "table", schema, name };
  if (type === "function") return { kind: "function", schema, name };
  return undefined;
}

function lintFinding(lint: Lint): FindingInput {
  const object = lintObject(lint);
  return {
    // oxlint-disable-next-line typescript/no-unnecessary-condition -- splinter can add levels this map does not know.
    severity: ADVISOR_SEVERITY[lint.level] ?? "warning",
    title: lint.title,
    message: `${lint.detail.replaceAll("\\`", "`")} [${lint.name}]`,
    target: object ? `${object.schema}.${object.name}` : lint.cache_key,
    help: lint.remediation,
    ...(object ? { object } : {}),
  };
}

/** A rule that reports one category of Supabase's advisors (splinter) as findings. */
export function advisorRule(
  code: string,
  category: AdvisorCategory,
  title: string,
  description: string,
  covered: (lint: Lint, context: DoctorContext) => boolean = () => false,
): Rule {
  return {
    code,
    severity: "warning",
    title,
    description,
    async check(context) {
      const { advisors } = context;
      if (!advisors) return [];
      if ("skipped" in advisors) {
        return [
          {
            severity: "info",
            message: `Skipped the ${category} advisor: ${advisors.skipped}`,
          },
        ];
      }
      try {
        return (await advisors.lints(category))
          .filter((lint) => !covered(lint, context))
          .map(lintFinding);
      } catch (cause) {
        return [
          {
            message: `The ${category} advisor could not run (${advisors.describe}): ${cause instanceof Error ? cause.message : String(cause)}`,
          },
        ];
      }
    },
  };
}

/**
 * splinter lints doctor's own rules report for the same table:
 * `multiple_permissive_policies` (BS207) and `unindexed_foreign_keys` (BS216).
 */
export function coveredByOwnRules(lint: Lint, context: DoctorContext): boolean {
  const code =
    lint.name === "multiple_permissive_policies"
      ? "BS207"
      : lint.name === "unindexed_foreign_keys"
        ? "BS216"
        : undefined;
  if (!code || !context.codes?.includes(code)) return false;
  const object = lintObject(lint);
  if (!object) return false;
  const table = exposed(context).find(
    (candidate) =>
      candidate.schema === object.schema && candidate.name === object.name,
  );
  if (!table) return false;
  return code === "BS207"
    ? permissiveOverlaps(table).length > 0
    : unindexedForeignKeys(table).length > 0;
}
