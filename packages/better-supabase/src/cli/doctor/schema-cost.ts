import type { FindingInput, Rule } from "./rules.ts";

import { catalogOf, exposedSchemas } from "./shared.ts";

/** A literal above this many characters is parsed again on every call. */
export const LITERAL_LIMIT = 1024;

/** Tables plus functions in one exposed schema before PostgREST's cache slows. */
const SCHEMA_OBJECT_LIMIT = 1500;

/** SQL text of the module files, in characters, before BS244 reports it. */
export const MODULE_SQL_LIMIT = 2_000_000;

const FUNCTION_START = /^create\s+(?:or\s+replace\s+)?function\s+([\w."]+)/im;
const SINGLE_QUOTED = /'(?:[^']|'')*'/g;
const DOLLAR_TAGGED = /\$(\w+)\$[\s\S]*?\$\1\$/g;

/** The longest quoted literal inside `body`, in characters. */
function longestLiteral(body: string): number {
  let longest = 0;

  for (const match of body.matchAll(SINGLE_QUOTED)) {
    longest = Math.max(longest, match[0].length - 2);
  }

  for (const match of body.matchAll(DOLLAR_TAGGED)) {
    longest = Math.max(longest, match[0].length - 2 * (match[1]!.length + 2));
  }

  return longest;
}

/** The `create function` statements of a SQL file, one string each. */
function functionStatements(text: string): string[] {
  return text
    .split(/\n(?=create\s+(?:or\s+replace\s+)?function\s)/i)
    .filter((chunk) => FUNCTION_START.test(chunk));
}

export const SCHEMA_COST_RULES: readonly Rule[] = [
  {
    code: "BS243",
    severity: "warning",
    title: "Security definer helper holds a large literal",
    description: `A \`security definer\` function whose body holds a quoted literal above ${LITERAL_LIMIT} characters (a permission map, a JSON catalog). Postgres parses the literal again on every call, and a policy helper runs once per table per statement. Read the data from a table, or parse it once and keep it with \`better_supabase.memo_get\` and \`memo_set\`. Reads the SQL files; saved snapshots work too.`,
    check: (context) =>
      (context.sqlFiles ?? []).flatMap((file) =>
        functionStatements(file.text).flatMap((statement): FindingInput[] => {
          if (!/security\s+definer/i.test(statement)) {
            return [];
          }

          const size = longestLiteral(statement);

          if (size <= LITERAL_LIMIT) {
            return [];
          }

          const name = FUNCTION_START.exec(statement)![1]!;

          // The library's own functions are generated; a project can't edit them.
          if (/^"?better_supabase"?\./.test(name)) {
            return [];
          }

          return [
            {
              message: `${name} is a security definer function with a ${size}-character literal (the limit is ${LITERAL_LIMIT}). Postgres parses it on every call. Store the data in a table, or parse it once per transaction with better_supabase.memo_get and memo_set.`,
              target: name,
              location: { file: file.path, line: 1 },
            },
          ];
        }),
      ),
  },
  {
    code: "BS244",
    severity: "warning",
    title: "Schema cache pressure",
    description: `PostgREST loads every table, function and relationship of the exposed schemas into its schema cache, at start and after each \`notify pgrst, 'reload schema'\`. A schema with more than ${SCHEMA_OBJECT_LIMIT} tables and functions, or generated module SQL above ${MODULE_SQL_LIMIT / 1_000_000} MB, makes that load slow. Expose fewer functions with \`gen.api.expose: "used"\`, and run DDL in one batch per deploy so the cache reloads once.`,
    check: (context) => {
      const catalog = catalogOf(context);
      const findings: FindingInput[] = [];

      for (const schema of exposedSchemas(context)) {
        const count =
          catalog.tables.filter((table) => table.schema === schema).length +
          catalog.functions.filter((fn) => fn.schema === schema).length;

        if (count > SCHEMA_OBJECT_LIMIT) {
          findings.push({
            message: `The exposed schema ${schema} has ${count} tables and functions (the limit is ${SCHEMA_OBJECT_LIMIT}), so PostgREST's schema cache loads slowly. Set gen.api.expose to "used" to emit API wrappers only for the functions your code calls, and apply DDL in one batch per deploy so the cache reloads once.`,
            target: `schema:${schema}`,
          });
        }
      }

      const size = (context.sqlFiles ?? [])
        .filter((file) => file.text.includes("@bsb-block"))
        .reduce((sum, file) => sum + file.text.length, 0);

      if (size > MODULE_SQL_LIMIT) {
        findings.push({
          message: `The generated module SQL is ${(size / 1_000_000).toFixed(1)} MB (the limit is ${MODULE_SQL_LIMIT / 1_000_000} MB). Install fewer blocks, or set gen.api.expose to "used".`,
          target: "modules:sql-size",
        });
      }

      return findings;
    },
  },
];
