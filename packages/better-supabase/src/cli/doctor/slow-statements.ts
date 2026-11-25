import type { Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";

/** Mean execution time in milliseconds from which a statement is reported. */
export const SLOW_STATEMENT_MS = 100;

/** Calls a statement needs before its mean counts; one slow run is noise. */
export const SLOW_STATEMENT_CALLS = 5;

interface StatementRow {
  readonly query: string;
  readonly calls: number | string;
  readonly mean_ms: number | string;
  readonly total_ms: number | string;
}

interface FunctionRow {
  readonly name: string;
  readonly calls: number | string;
  readonly mean_ms: number | string;
}

const oneLine = (text: string): string =>
  text.replaceAll(/\s+/g, " ").trim().slice(0, 120);

export const SLOW_STATEMENT_RULES: readonly Rule[] = [
  {
    code: "BS732",
    severity: "warning",
    title: "Slow statements in pg_stat_statements",
    description: `A statement the API roles ran at least ${SLOW_STATEMENT_CALLS} times has a mean execution time of ${SLOW_STATEMENT_MS} ms or more in \`pg_stat_statements\`, or a function has the same mean in \`pg_stat_user_functions\` (\`track_functions\`). The planning and executor start-up of a SQL function body count toward its call, so an RPC that is slow here often has a policy or a function inside it that is. Run \`explain (analyze, buffers)\` as the signed-in role with its claims set, or \`better-supabase doctor --explain\`. It reads statistics from the running database, so it needs a database, and it reports nothing when the extension is not installed or nothing has run yet.`,
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      try {
        const statements = await db.query<StatementRow>(
          `select s.query, s.calls::int8 as calls, (s.total_exec_time / nullif(s.calls, 0))::float8 as mean_ms, s.total_exec_time::float8 as total_ms from pg_stat_statements s join pg_roles r on r.oid = s.userid where r.rolname in ('authenticated', 'anon', 'service_role') and s.query not ilike '%pg_stat_statements%' and s.calls >= ${SLOW_STATEMENT_CALLS} and s.total_exec_time / s.calls >= ${SLOW_STATEMENT_MS} order by s.total_exec_time desc limit 10`,
        );

        const functions = await db.query<FunctionRow>(
          `select f.schemaname || '.' || f.funcname as name, f.calls::int8 as calls, (f.total_time / nullif(f.calls, 0))::float8 as mean_ms from pg_stat_user_functions f where f.schemaname in ('public', 'better_supabase') and f.calls >= ${SLOW_STATEMENT_CALLS} and f.total_time / f.calls >= ${SLOW_STATEMENT_MS} order by f.total_time desc limit 10`,
        );

        return [
          ...statements.map((row) => ({
            message: `A statement ran ${Number(row.calls)} times with a mean of ${Number(row.mean_ms).toFixed(1)} ms (${Number(row.total_ms).toFixed(0)} ms in total): ${oneLine(row.query)}`,
          })),
          ...functions.map((row) => ({
            message: `${row.name}() ran ${Number(row.calls)} times with a mean of ${Number(row.mean_ms).toFixed(1)} ms.`,
            target: row.name,
          })),
        ];
      } catch (cause) {
        // `pg_stat_statements` missing is a normal state of a fresh database.
        const text = errorText(cause);

        return /pg_stat_statements|does not exist/i.test(text)
          ? []
          : [
              {
                message: `Could not read the statement statistics (${db.describe}): ${text}`,
              },
            ];
      }
    },
  },
];
