import type { AdvisorCategory, AdvisorSource, Lint } from "./advisors.ts";
import type {
  DoctorContext,
  FindingInput,
  Rule,
  Severity,
  SqlObject,
} from "./rules.ts";

/** One request per advisor category, shared by the advisor rules and the rules that defer to them. */
const fetched = new WeakMap<
  AdvisorSource,
  Map<AdvisorCategory, Promise<readonly Lint[]>>
>();

function lintsOf(
  advisors: AdvisorSource,
  category: AdvisorCategory,
): Promise<readonly Lint[]> {
  let byCategory = fetched.get(advisors);
  if (!byCategory) {
    byCategory = new Map();
    fetched.set(advisors, byCategory);
  }
  let lints = byCategory.get(category);
  if (!lints) {
    lints = advisors.lints(category);
    byCategory.set(category, lints);
  }
  return lints;
}

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
        return (await lintsOf(advisors, category)).map(lintFinding);
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

/** The performance advisor rule the duplicate rules defer to. */
const PERFORMANCE_ADVISOR = "BS200";

/**
 * The tables splinter reports `lint` for (`schema.table`), when the
 * performance advisor runs in this run and its lints loaded. A rule that
 * repeats the lint (BS207, BS216) drops its findings for these tables; with
 * `undefined` (no advisors, a saved snapshot, an advisor error, or BS200 not
 * in the run) it reports them itself.
 */
export async function splinterTables(
  context: DoctorContext,
  lint: string,
): Promise<ReadonlySet<string> | undefined> {
  const { advisors } = context;
  if (!advisors || "skipped" in advisors) return undefined;
  if (!context.codes?.includes(PERFORMANCE_ADVISOR)) return undefined;
  let lints: readonly Lint[];
  try {
    lints = await lintsOf(advisors, "performance");
  } catch {
    return undefined;
  }
  return new Set(
    lints.flatMap((entry) => {
      if (entry.name !== lint) return [];
      const object = lintObject(entry);
      return object ? [`${object.schema}.${object.name}`] : [];
    }),
  );
}
