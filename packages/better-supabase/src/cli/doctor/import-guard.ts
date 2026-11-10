import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

/** One app row trigger and the function it runs. */
export interface RowTrigger {
  readonly name: string;
  readonly table: string;
  readonly fn: string;
  readonly path: string;
}

const IDENT = String.raw`(?:"[^"]+"|[\w$]+)(?:\.(?:"[^"]+"|[\w$]+))?`;

const TRIGGER = new RegExp(
  String.raw`create\s+(?:or\s+replace\s+)?(?:constraint\s+)?trigger\s+("[^"]+"|[\w$]+)\s+(?:before|after|instead\s+of)\s+[^;]*?\bon\s+(${IDENT})([^;]*?)execute\s+(?:function|procedure)\s+(${IDENT})`,
  "gi",
);

const FUNCTION = new RegExp(
  String.raw`create\s+(?:or\s+replace\s+)?function\s+(${IDENT})\s*\([^$]*?\$(\w*)\$([\s\S]*?)\$\2\$`,
  "gi",
);

const bare = (name: string): string =>
  (name.split(".").pop() ?? name).replaceAll('"', "").toLowerCase();

const sources = (
  context: DoctorContext,
): readonly { readonly path: string; readonly text: string }[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

/**
 * The row triggers the app declares (not `bsb_*`), with the function each one
 * runs, from the schema files.
 */
export function appRowTriggers(
  files: readonly { readonly path: string; readonly text: string }[],
): RowTrigger[] {
  return files.flatMap((file) =>
    [...file.text.matchAll(TRIGGER)].flatMap((match): RowTrigger[] => {
      const [, name = "", table = "", , fn = ""] = match;

      if (
        name.replaceAll('"', "").toLowerCase().startsWith("bsb_") ||
        !/for\s+each\s+row/i.test(match[0])
      ) {
        return [];
      }

      return [
        {
          name: name.replaceAll('"', ""),
          table: table.replaceAll('"', ""),
          fn: bare(fn),
          path: file.path,
        },
      ];
    }),
  );
}

/** The body of each function in the files, by its unqualified name. */
export function functionBodies(
  files: readonly { readonly path: string; readonly text: string }[],
): ReadonlyMap<string, string> {
  const bodies = new Map<string, string>();

  for (const file of files) {
    for (const match of file.text.matchAll(FUNCTION)) {
      bodies.set(bare(match[1] ?? ""), match[3] ?? "");
    }
  }

  return bodies;
}

/**
 * Row triggers whose function never calls `better_supabase.importing()`, so an
 * import runs them for every row.
 */
export function unguardedRowTriggers(
  files: readonly { readonly path: string; readonly text: string }[],
): RowTrigger[] {
  const bodies = functionBodies(files);

  return appRowTriggers(files).filter((trigger) => {
    const body = bodies.get(trigger.fn);

    // A function outside the schema files can't be read, so it isn't judged.
    return body !== undefined && !/\bimporting\s*\(\s*\)/i.test(body);
  });
}

export const IMPORT_GUARD_RULES: readonly Rule[] = [
  {
    code: "BS633",
    severity: "info",
    title: "An app row trigger has no importing() guard",
    description:
      "An import writes thousands of rows in one transaction, and an app row trigger runs for each of them. A trigger that sends, enqueues or recomputes something per row usually wants to skip an import and do that work once at the end. Wrap the body in `if not better_supabase.importing() then ... end if`, or return early when it is true. Doctor reads the trigger functions in the schema files and skips triggers named `bsb_*`.",
    check(context) {
      return unguardedRowTriggers(sources(context)).map(
        (trigger): FindingInput => ({
          message: `Trigger ${trigger.name} on ${trigger.table} runs ${trigger.fn}() for each row, and ${trigger.fn} never calls better_supabase.importing(), so an import runs it once per imported row.`,
          target: `${trigger.table}.${trigger.name}`,
          help: "Return early from the function when better_supabase.importing() is true, then do the work once after the import.",
        }),
      );
    },
  },
];
