import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import {
  codeStatementsOf,
  indexOfWords,
  nameAt,
  wordsAt,
} from "../schema-reader/index.ts";

/** One app row trigger and the function it runs. */
export interface RowTrigger {
  readonly name: string;
  readonly table: string;
  readonly fn: string;
  readonly path: string;
}

const schemaOf = (name: string): string | undefined =>
  name.includes(".")
    ? name.split(".")[0]!.replaceAll('"', "").toLowerCase()
    : undefined;

/**
 * The schemas the authorization provider's functions live in
 * (`authorization.requires`): its triggers guard its own integrity, so an
 * import must run them.
 */
const providerSchemas = (context: DoctorContext): ReadonlySet<string> =>
  new Set(
    (context.config.authorization?.requires ?? []).flatMap((entry) => {
      const schema = schemaOf(entry.function);

      return schema === undefined ? [] : [schema];
    }),
  );

const sources = (
  context: DoctorContext,
): readonly { readonly path: string; readonly text: string }[] =>
  (context.sqlFiles ?? []).filter(
    (file) =>
      !file.path.includes("migrations/") &&
      !file.path.includes("better-supabase-data/"),
  );

/**
 * The row triggers the app declares (not `bsb_*`, and not running a function in
 * one of `skipSchemas`), with the function each one runs, from the schema
 * files.
 */
export function appRowTriggers(
  files: readonly { readonly path: string; readonly text: string }[],
  skipSchemas: ReadonlySet<string> = new Set(),
): RowTrigger[] {
  return files.flatMap((file) =>
    codeStatementsOf(file.text).flatMap(({ tokens }): RowTrigger[] => {
      const head = wordsAt(tokens, 0, "create", "or", "replace") ? 3 : 1;
      const constraint = wordsAt(tokens, head, "constraint") ? 1 : 0;

      const created = wordsAt(tokens, head + constraint, "trigger")
        ? nameAt(tokens, head + constraint + 1)
        : undefined;

      if (created?.parts.length !== 1) {
        return [];
      }

      const on = indexOfWords(tokens, created.next, "on");
      const table = on === -1 ? undefined : nameAt(tokens, on + 1);
      const execute = indexOfWords(tokens, created.next, "execute");
      const fn = execute === -1 ? undefined : nameAt(tokens, execute + 2);

      if (
        table === undefined ||
        fn === undefined ||
        !(
          wordsAt(tokens, execute, "execute", "function") ||
          wordsAt(tokens, execute, "execute", "procedure")
        ) ||
        indexOfWords(tokens, created.next, "for", "each", "row") === -1
      ) {
        return [];
      }

      const name = created.parts[0] ?? "";
      const schema = fn.parts.length > 1 ? fn.parts[0] : undefined;

      if (
        name.toLowerCase().startsWith("bsb_") ||
        (schema !== undefined && skipSchemas.has(schema.toLowerCase()))
      ) {
        return [];
      }

      return [
        {
          name,
          table: table.parts.join("."),
          fn: (fn.parts.at(-1) ?? "").toLowerCase(),
          path: file.path,
        },
      ];
    }),
  );
}

/**
 * Whether each function the files create calls `better_supabase.importing()`,
 * by its unqualified name, the last create of a name winning.
 */
function importGuards(
  files: readonly { readonly path: string; readonly text: string }[],
): ReadonlyMap<string, boolean> {
  const guards = new Map<string, boolean>();

  for (const file of files) {
    for (const { tokens } of codeStatementsOf(file.text)) {
      const head = wordsAt(tokens, 0, "create", "or", "replace") ? 3 : 1;

      const created = wordsAt(tokens, head, "function")
        ? nameAt(tokens, head + 1)
        : undefined;

      if (created === undefined || tokens[created.next]?.text !== "(") {
        continue;
      }

      const body = tokens.filter((token) => token.depth > 0);

      guards.set(
        (created.parts.at(-1) ?? "").toLowerCase(),
        body.some(
          (token, at) =>
            wordsAt(body, at, "importing") &&
            body[at + 1]?.text === "(" &&
            body[at + 2]?.text === ")" &&
            token.kind === "word",
        ),
      );
    }
  }

  return guards;
}

/**
 * Row triggers whose function never calls `better_supabase.importing()`, so an
 * import runs them for every row.
 */
export function unguardedRowTriggers(
  files: readonly { readonly path: string; readonly text: string }[],
  skipSchemas: ReadonlySet<string> = new Set(),
): RowTrigger[] {
  const guards = importGuards(files);

  return appRowTriggers(files, skipSchemas).filter(
    // A function outside the schema files can't be read, so it isn't judged.
    (trigger) => guards.get(trigger.fn) === false,
  );
}

export const IMPORT_GUARD_RULES: readonly Rule[] = [
  {
    code: "BS633",
    severity: "info",
    title: "An app row trigger has no importing() guard",
    description:
      "An import writes thousands of rows in one transaction, and an app row trigger runs for each of them. A trigger that sends, enqueues or recomputes something per row usually wants to skip an import and do that work once at the end. Wrap the body in `if not better_supabase.importing() then ... end if`, or return early when it is true. Doctor reads the trigger functions in the schema files and skips triggers named `bsb_*` and triggers whose function lives in a schema of the authorization provider's functions (`authorization.requires`), which guard the provider's own rows.",
    check(context) {
      return unguardedRowTriggers(
        sources(context),
        providerSchemas(context),
      ).map((trigger): FindingInput => ({
        message: `Trigger ${trigger.name} on ${trigger.table} runs ${trigger.fn}() for each row, and ${trigger.fn} never calls better_supabase.importing(), so an import runs it once per imported row.`,
        target: `${trigger.table}.${trigger.name}`,
        help: "Return early from the function when better_supabase.importing() is true, then do the work once after the import.",
      }));
    },
  },
];
