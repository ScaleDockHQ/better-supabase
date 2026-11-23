import type { Rule } from "./rules.ts";

export const SCHEMA_READ_RULES: readonly Rule[] = [
  {
    code: "BS731",
    severity: "warning",
    title: "A SQL file does not parse",
    description:
      "The schema reader parses each SQL file with the grammar of `db.major_version` in `supabase/config.toml` (15, 16 or 17; 17 when unset). A file it rejects keeps no facts, so every rule that reads tables, policies or functions from it sees nothing there, and `gen` stops on it. Doctor names the file, the line and column, the parser's message and the Postgres version whose grammar rejected it. Fix the statement, or set `db.major_version` when the file uses syntax of another version.",
    check: (context) =>
      (context.schemaReadErrors ?? []).map((error) => ({
        message: `${error.path}:${String(error.line)}:${String(error.column)} does not parse with the Postgres ${String(error.major)} grammar: ${error.message}. The rules that read SQL skip this file until it parses.`,
        target: error.path,
        location: { file: error.path, line: error.line },
      })),
  },
];
