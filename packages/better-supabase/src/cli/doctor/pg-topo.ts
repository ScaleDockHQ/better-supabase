import type {
  AnalyzeResult,
  Diagnostic,
  ObjectRef,
  StatementId,
} from "@supabase/pg-topo";
import type * as PgTopoModule from "@supabase/pg-topo";

import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { PLATFORM_SCHEMAS } from "../in-stack-diff.ts";
import { declarativeSchemasDir } from "../supabase-config.ts";

type PgTopo = typeof PgTopoModule;

/** One analysis per file list, shared by the five rules that read it. */
const analyses = new WeakMap<
  readonly TextFile[],
  Promise<Analysis | undefined>
>();

interface Analysis {
  readonly result: AnalyzeResult;
  readonly files: readonly TextFile[];
}

/** The declarative schema files, which are the input pg-delta orders. */
function schemaFiles(context: DoctorContext): readonly TextFile[] {
  const dir = context.configToml
    ? declarativeSchemasDir(context.configToml, "pg-delta")
    : "supabase/schemas";

  const prefix = `${dir}/`;

  return (context.sqlFiles ?? [])
    .filter((file) => file.path.startsWith(prefix))
    .toSorted((a, b) => (a.path < b.path ? -1 : 1));
}

/**
 * Pg-topo is a dependency of the package that only the doctor and `db diff`
 * use, so it loads on first use to keep CLI startup fast (invariant 12). An
 * install that lacks it skips the group.
 */
async function loadPgTopo(): Promise<PgTopo | undefined> {
  try {
    return await import("@supabase/pg-topo");
  } catch {
    return undefined;
  }
}

function analysisOf(context: DoctorContext): Promise<Analysis | undefined> {
  const files = schemaFiles(context);
  const source = context.sqlFiles ?? [];
  let analysis = analyses.get(source);

  if (analysis === undefined) {
    analysis =
      files.length === 0
        ? Promise.resolve(undefined)
        : loadPgTopo().then(async (topo) =>
            topo === undefined
              ? undefined
              : {
                  result: await topo.analyzeAndSort(
                    files.map((file) => file.text),
                  ),
                  files,
                },
          );
    analyses.set(source, analysis);
  }

  return analysis;
}

/** The file and line a statement id names; ids are `<input:n>` for entry n. */
function locate(
  analysis: Analysis,
  id: StatementId | undefined,
): { file: string; line: number } | undefined {
  const index = /^<input:(\d+)>$/.exec(id?.filePath ?? "")?.[1];
  const file = index === undefined ? undefined : analysis.files[Number(index)];

  if (file === undefined || id === undefined) {
    return undefined;
  }

  const offset = id.sourceOffset ?? 0;

  return {
    file: file.path,
    line: file.text.slice(0, offset).split("\n").length,
  };
}

const refText = (ref: ObjectRef): string =>
  `${ref.kind} ${ref.schema === undefined ? "" : `${ref.schema}.`}${ref.name}`;

/** Built-in types pg-topo's own list lacks, so it reads them as `public.<name>`. */
const PG_TOPO_BUILTIN_TYPES: ReadonlySet<string> = new Set([
  "pg_snapshot",
  "xid8",
]);

/**
 * Objects the platform or an extension supplies. pg-topo reads an unqualified
 * function as `public.<name>`, so a missing function in `public` is not
 * reported (it is usually a built-in); roles, extensions and languages come
 * from the platform. A foreign key also requires the referenced constraint, so
 * constraints are left to the table's own finding.
 */
function isPlatformRef(ref: ObjectRef): boolean {
  // A `schema` ref names the schema in `name`.
  if (ref.kind === "schema" && PLATFORM_SCHEMAS.has(ref.name)) {
    return true;
  }

  if (ref.kind === "type" && (ref.schema ?? "public") === "public") {
    return PG_TOPO_BUILTIN_TYPES.has(ref.name);
  }

  if (
    ref.kind === "role" ||
    ref.kind === "extension" ||
    ref.kind === "language" ||
    ref.kind === "constraint"
  ) {
    return true;
  }

  if (ref.schema !== undefined && PLATFORM_SCHEMAS.has(ref.schema)) {
    return true;
  }

  return ref.kind === "function" && (ref.schema ?? "public") === "public";
}

function findings(
  analysis: Analysis | undefined,
  codes: readonly Diagnostic["code"][],
  keep: (diagnostic: Diagnostic) => boolean,
  message: (diagnostic: Diagnostic, where: string) => string,
): FindingInput[] {
  if (analysis === undefined) {
    return [];
  }

  // The module files the library renders under `_better_supabase/` replace
  // their own functions and triggers and read dynamic sequences; the app can
  // only act on the findings in its own files.
  const own = (diagnostic: Diagnostic): boolean =>
    !(locate(analysis, diagnostic.statementId)?.file ?? "").includes(
      "/_better_supabase/",
    );

  return analysis.result.diagnostics
    .filter(
      (diagnostic) =>
        codes.includes(diagnostic.code) && keep(diagnostic) && own(diagnostic),
    )
    .map((diagnostic) => {
      const at = locate(analysis, diagnostic.statementId);

      return {
        message: message(diagnostic, at?.file ?? "a schema file"),
        ...(at === undefined
          ? {}
          : { target: at.file, location: { file: at.file, line: at.line } }),
      };
    });
}

/**
 * Pg-topo's static analysis of the declarative schema files. It needs no
 * database, so the group runs in every project that has files under
 * `supabase/schemas`. It is advisory: pg-topo cannot read dynamic SQL, so the
 * messages point at `-- pg-topo:` annotations where that is the fix.
 */
export const PG_TOPO_RULES: readonly Rule[] = [
  {
    code: "BS720",
    severity: "error",
    title: "A schema file does not parse",
    description:
      "pg-topo could not parse a file under `supabase/schemas`. pg-delta loads the same files, so it stops on the same error. The whole file is skipped by the analysis, which hides the findings of BS721 to BS723 for it.",
    check: async (context) =>
      findings(
        await analysisOf(context),
        ["PARSE_ERROR"],
        () => true,
        (diagnostic) => diagnostic.message,
      ),
  },
  {
    code: "BS721",
    severity: "warning",
    title: "A schema file uses an object no file creates",
    description:
      "A statement under `supabase/schemas` refers to a table, view, type, sequence or schema that no schema file creates, outside the platform's schemas. pg-delta loads the files into an empty database, so the load fails or runs the statement out of order. Create the object in a schema file, or add `-- pg-topo:provides <kind>:<schema>.<name>` above the statement that creates it when it does so through dynamic SQL.",
    check: async (context) => {
      const analysis = await analysisOf(context);

      // pg-topo matches a call to a function by its argument types, so a call
      // that leaves out arguments with defaults, or passes untyped literals,
      // finds no producer. A function some file creates under that name is
      // not reported.
      const created = new Set(
        (analysis?.result.ordered ?? []).flatMap((node) =>
          node.provides
            .filter(
              (ref) => ref.kind === "function" || ref.kind === "procedure",
            )
            .map((ref) => `${ref.schema ?? "public"}.${ref.name}`),
        ),
      );

      const missing = (ref: ObjectRef): boolean =>
        !isPlatformRef(ref) &&
        !(
          (ref.kind === "function" || ref.kind === "procedure") &&
          created.has(`${ref.schema ?? "public"}.${ref.name}`)
        );

      return findings(
        analysis,
        ["UNRESOLVED_DEPENDENCY"],
        (diagnostic) => (diagnostic.objectRefs ?? []).some(missing),
        (diagnostic, where) =>
          `${where} needs ${(diagnostic.objectRefs ?? [])
            .filter(missing)
            .map(refText)
            .join(
              ", ",
            )}, which no schema file creates. Create it in a schema file, or declare it with \`-- pg-topo:provides\` where dynamic SQL creates it.`,
      );
    },
  },
  {
    code: "BS722",
    severity: "warning",
    title: "Two schema statements create the same object",
    description:
      "More than one statement under `supabase/schemas` creates the same object (often a policy or function copied between files). pg-delta keeps the last one it loads, so the result depends on file order.",
    check: async (context) =>
      findings(
        await analysisOf(context),
        ["DUPLICATE_PRODUCER"],
        // Every module file opens with `create schema if not exists` and
        // `create extension if not exists`, which are idempotent, so repeats
        // of those are not a copied definition.
        (diagnostic) =>
          !(diagnostic.objectRefs ?? []).every(
            (ref) => ref.kind === "schema" || ref.kind === "extension",
          ) || (diagnostic.objectRefs ?? []).length === 0,
        (diagnostic, where) =>
          `${where}: ${diagnostic.message.split(". This statement")[0] ?? diagnostic.message}. Keep one definition.`,
      ),
  },
  {
    code: "BS723",
    severity: "warning",
    title: "Schema statements depend on each other in a cycle",
    description:
      "Statements under `supabase/schemas` require each other (two functions that call each other, or a table and a function that use one another). pg-delta cannot order a cycle, so it loads them in a fixed order and may fail. Break the cycle with a deferred reference, or move one statement into a migration. A `-- pg-topo:depends_on` annotation removes a wrong edge.",
    check: async (context) =>
      findings(
        await analysisOf(context),
        ["CYCLE_DETECTED"],
        () => true,
        (diagnostic, where) =>
          `${where} is part of a dependency cycle (${diagnostic.message}).`,
      ),
  },
  {
    code: "BS724",
    severity: "error",
    title: "A pg-topo annotation is invalid",
    description:
      "A `-- pg-topo:` comment above a statement under `supabase/schemas` names a directive pg-topo does not know, or a value it cannot read. The supported directives are `phase`, `depends_on`, `requires` and `provides`.",
    check: async (context) =>
      findings(
        await analysisOf(context),
        ["INVALID_ANNOTATION"],
        () => true,
        (diagnostic, where) => `${where}: ${diagnostic.message}`,
      ),
  },
];
