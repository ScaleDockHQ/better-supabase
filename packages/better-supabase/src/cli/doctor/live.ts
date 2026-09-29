import type { CatalogTable } from '../introspect/types.ts';
import type { DoctorContext, FindingInput, Rule } from './rules.ts';

import { catalogOf, exposed, qualified, tableObject } from './shared.ts';

/** The database doctor checks, for statistics and plans. */
export interface LiveDatabase {
  readonly describe: string;
  /** Runs statements one at a time on one session (false for the Management API). */
  readonly session: boolean;
  query<R = Record<string, unknown>>(sql: string): Promise<R[]>;
}

/** What `--explain` plans, and as whom. */
export interface ExplainRequest {
  /** `customers` or `public.customers`. */
  readonly tables: readonly string[];
  /** `request.jwt.claims`; `role` picks the Postgres role (default `anon`). */
  readonly claims: Readonly<Record<string, unknown>>;
}

/** Statements slower than this (ms, mean) with more calls than `SLOW_CALLS` are BS209. */
export const SLOW_MEAN_MS = 50;
export const SLOW_CALLS = 1000;
/** Rows `--explain` reads, like a `findMany()` under Supabase's default `max_rows`. */
export const EXPLAIN_LIMIT = 1000;

const escape = (name: string): string =>
  name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

const ident = (name: string): string => `"${name.replaceAll('"', '""')}"`;
const literal = (text: string): string => `'${text.replaceAll("'", "''")}'`;

const errorText = (cause: unknown): string =>
  cause instanceof Error ? cause.message : String(cause);

const oneLine = (query: string, max = 160): string => {
  const flat = query.replace(/\s+/g, ' ').trim();
  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
};

const plural = (count: number, word: string): string =>
  `${count} ${word}${count === 1 ? '' : 's'}`;

const megabytes = (bytes: number): string =>
  `${(bytes / 1024 / 1024).toFixed(1)} MB`;

/** The schema `pg_stat_statements` lives in, when the extension is installed. */
async function statementsView(db: LiveDatabase): Promise<string | undefined> {
  const [row] = await db.query<{ schema: string }>(
    `select n.nspname as schema from pg_extension e join pg_namespace n on n.oid = e.extnamespace where e.extname = 'pg_stat_statements'`,
  );
  return row ? `${ident(row.schema)}.pg_stat_statements` : undefined;
}

/** The first exposed table a statement names, to locate it in the SQL files. */
function tableIn(
  query: string,
  tables: readonly CatalogTable[],
): CatalogTable | undefined {
  return tables.find((table) => {
    const schema = escape(table.schema);
    const name = escape(table.name);
    return new RegExp(
      `(?:"${schema}"|\\b${schema})\\.(?:"${name}"|${name}\\b)`,
    ).test(query);
  });
}

const live = (
  context: DoctorContext,
): LiveDatabase | { readonly skipped: string } | undefined => context.database;

interface PlanNode {
  readonly 'Node Type': string;
  readonly 'Relation Name'?: string;
  readonly 'Parent Relationship'?: string;
  readonly 'Subplan Name'?: string;
  readonly 'Actual Total Time'?: number;
  readonly 'Actual Loops'?: number;
  readonly Plans?: readonly PlanNode[];
}

interface ExplainOutput {
  readonly Plan: PlanNode;
  readonly 'Execution Time'?: number;
}

interface FunctionTime {
  readonly name: string;
  readonly calls: number;
  readonly selfTime: number;
}

/**
 * Function calls and self time so far in this transaction. The view can
 * still hold unflushed counts from earlier transactions, so callers diff two
 * readings.
 */
async function functionTimes(
  db: LiveDatabase,
): Promise<Map<string, { calls: number; selfTime: number }>> {
  const rows = await db.query<{
    name: string;
    calls: number | string;
    self_time: number | string;
  }>(
    `select schemaname || '.' || funcname as name, calls, self_time from pg_stat_xact_user_functions`,
  );
  return new Map(
    rows.map((row) => [
      row.name,
      { calls: Number(row.calls), selfTime: Number(row.self_time) },
    ]),
  );
}

export interface PlanSummary {
  /** `Seq Scan on customers 1.20 ms ×1`, depth first. */
  readonly nodes: readonly string[];
  readonly initPlans: number;
  /** SubPlans that ran more than once: once per row. */
  readonly perRowSubPlans: readonly string[];
  readonly executionMs: number;
}

/** Node types, timings and loops of an `EXPLAIN (ANALYZE, FORMAT JSON)` plan; never rows. */
export function summarizePlan(output: ExplainOutput): PlanSummary {
  const nodes: string[] = [];
  const perRowSubPlans: string[] = [];
  let initPlans = 0;
  const walk = (node: PlanNode): void => {
    const loops = node['Actual Loops'] ?? 1;
    const ms = (node['Actual Total Time'] ?? 0).toFixed(2);
    const on = node['Relation Name'] ? ` on ${node['Relation Name']}` : '';
    const sub = node['Subplan Name'] ? `${node['Subplan Name']}: ` : '';
    nodes.push(`${sub}${node['Node Type']}${on} ${ms} ms ×${loops}`);
    if (node['Parent Relationship'] === 'InitPlan') initPlans += 1;
    if (node['Parent Relationship'] === 'SubPlan' && loops > 1)
      perRowSubPlans.push(`${sub}${node['Node Type']}${on} ×${loops}`);
    for (const child of node.Plans ?? []) walk(child);
  };
  walk(output.Plan);
  return {
    nodes,
    initPlans,
    perRowSubPlans,
    executionMs: output['Execution Time'] ?? 0,
  };
}

const ROLE = /^[a-z_][a-z0-9_]*$/;

async function explainTable(
  db: LiveDatabase,
  table: CatalogTable,
  claims: Readonly<Record<string, unknown>>,
): Promise<{ summary: PlanSummary; functions: FunctionTime[] | undefined }> {
  const role = typeof claims['role'] === 'string' ? claims['role'] : 'anon';
  if (!ROLE.test(role)) throw new Error(`Invalid role "${role}" in the claims`);
  await db.query('begin');
  try {
    await db.query(`set local statement_timeout = '30s'`);
    let tracked = true;
    await db.query('savepoint bs_track');
    try {
      await db.query(`set local track_functions = 'all'`);
      await db.query('release savepoint bs_track');
    } catch {
      tracked = false;
      await db.query('rollback to savepoint bs_track');
    }
    await db.query(
      `select set_config('request.jwt.claims', ${literal(JSON.stringify(claims))}, true)`,
    );
    const before = tracked ? await functionTimes(db) : new Map();
    await db.query(`set local role ${ident(role)}`);
    const [row] = await db.query<{ 'QUERY PLAN': unknown }>(
      `explain (analyze, buffers, format json) select * from ${ident(table.schema)}.${ident(table.name)} limit ${EXPLAIN_LIMIT}`,
    );
    const raw = row?.['QUERY PLAN'];
    const plan = (typeof raw === 'string' ? JSON.parse(raw) : raw) as
      | ExplainOutput[]
      | undefined;
    if (!plan?.[0]) throw new Error('EXPLAIN returned no plan');
    const functions = tracked
      ? [...(await functionTimes(db))]
          .map(([name, after]): FunctionTime => {
            const start = before.get(name);
            return {
              name,
              calls: after.calls - (start?.calls ?? 0),
              selfTime: after.selfTime - (start?.selfTime ?? 0),
            };
          })
          .filter((fn) => fn.calls > 0)
          .sort((a, b) => b.selfTime - a.selfTime)
      : undefined;
    return { summary: summarizePlan(plan[0]), functions };
  } finally {
    await db.query('rollback');
  }
}

function resolveTable(
  context: DoctorContext,
  name: string,
): CatalogTable | undefined {
  return name.includes('.')
    ? catalogOf(context).tables.find((table) => qualified(table) === name)
    : exposed(context).find((table) => table.name === name);
}

export const LIVE_RULES: readonly Rule[] = [
  {
    code: 'BS208',
    severity: 'warning',
    title: 'Queries spill to temporary files',
    description:
      'Sorts and hashes that exceed `work_mem` write temporary files, which is slow. Reads `pg_stat_database` and, when installed, the top statements from `pg_stat_statements`.',
    async check(context) {
      const db = live(context);
      if (!db || 'skipped' in db) return [];
      try {
        const [stats] = await db.query<{
          temp_files: number | string;
          temp_bytes: number | string;
          work_mem: string;
        }>(
          `select temp_files, temp_bytes, current_setting('work_mem') as work_mem from pg_stat_database where datname = current_database()`,
        );
        const files = Number(stats?.temp_files ?? 0);
        if (files === 0) return [];
        let top = '';
        const view = await statementsView(db);
        if (view) {
          const statements = await db
            .query<{ query: string; temp_blks_written: number | string }>(
              `select query, temp_blks_written from ${view} where temp_blks_written > 0 order by temp_blks_written desc limit 5`,
            )
            .catch(() => []);
          if (statements.length > 0) {
            top = ` Top statements by temporary blocks written: ${statements
              .map(
                (statement) =>
                  `${oneLine(statement.query, 100)} (${statement.temp_blks_written} blocks)`,
              )
              .join('; ')}.`;
          }
        }
        return [
          {
            message: `${files} temporary files (${megabytes(Number(stats?.temp_bytes ?? 0))}) since the statistics were reset; work_mem is ${stats?.work_mem}. Add indexes so large sorts go away, or raise work_mem for the role that runs them.${top}`,
            target: 'pg_stat_database:temp_files',
          },
        ];
      } catch (cause) {
        return [
          {
            severity: 'info',
            message: `Could not read pg_stat_database (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
  {
    code: 'BS209',
    severity: 'warning',
    title: 'Slow frequent statements',
    description: `Statements from \`pg_stat_statements\` with a mean time above ${SLOW_MEAN_MS} ms and more than ${SLOW_CALLS} calls. Runs with \`--stats\`.`,
    async check(context) {
      if (!context.stats) return [];
      const db = live(context);
      if (!db) return [];
      if ('skipped' in db)
        return [
          {
            severity: 'info',
            message: `Skipped --stats: ${db.skipped}`,
          },
        ];
      try {
        const view = await statementsView(db);
        if (!view) {
          return [
            {
              severity: 'info',
              message:
                'pg_stat_statements is not installed, so --stats has nothing to read. Run `create extension pg_stat_statements with schema extensions;`.',
            },
          ];
        }
        const statements = await db.query<{
          queryid: string;
          query: string;
          calls: number | string;
          mean_exec_time: number | string;
        }>(
          `select queryid::text as queryid, query, calls, mean_exec_time from ${view} where calls > ${SLOW_CALLS} and mean_exec_time > ${SLOW_MEAN_MS} order by total_exec_time desc limit 20`,
        );
        const tables = exposed(context);
        return statements.map((statement): FindingInput => {
          const table = tableIn(statement.query, tables);
          return {
            message: `${Number(statement.mean_exec_time).toFixed(1)} ms mean over ${statement.calls} calls: ${oneLine(statement.query)}`,
            target: `pg_stat_statements:${statement.queryid}`,
            ...(table ? { object: tableObject(table) } : {}),
          };
        });
      } catch (cause) {
        return [
          {
            severity: 'info',
            message: `Could not read pg_stat_statements (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
  {
    code: 'BS212',
    severity: 'info',
    title: 'RLS plan for a table',
    description: `\`--explain <tables>\` runs \`EXPLAIN (ANALYZE, BUFFERS)\` on \`select * from <table> limit ${EXPLAIN_LIMIT}\` as the given claims, in a transaction that is rolled back. It reports node types, timings and loops, never rows, and warns when a policy SubPlan runs once per row.`,
    async check(context) {
      const request = context.explain;
      if (!request) return [];
      const db = live(context);
      if (!db || 'skipped' in db || !db.session) {
        return [
          {
            severity: 'warning',
            message: `--explain needs a direct database connection (local stack or --db-url)${db && 'skipped' in db ? `: ${db.skipped}` : '.'}`,
          },
        ];
      }
      const who =
        typeof request.claims['sub'] === 'string'
          ? `${String(request.claims['role'] ?? 'anon')} ${request.claims['sub']}`
          : String(request.claims['role'] ?? 'anon');
      const findings: FindingInput[] = [];
      for (const name of request.tables) {
        const table = resolveTable(context, name);
        if (!table) {
          findings.push({
            severity: 'warning',
            message: `--explain: no table "${name}" in the exposed schemas; qualify tables in other schemas, like better_supabase.memberships.`,
          });
          continue;
        }
        try {
          const { summary, functions } = await explainTable(
            db,
            table,
            request.claims,
          );
          const helpers = functions
            ? functions.length > 0
              ? ` Function time: ${functions
                  .map((fn) => {
                    const self = fn.selfTime;
                    const share =
                      summary.executionMs > 0
                        ? Math.round((self / summary.executionMs) * 100)
                        : 0;
                    return `${fn.name} ${self.toFixed(2)} ms over ${plural(fn.calls, 'call')} (${share}%)`;
                  })
                  .join(', ')}.`
              : ' No tracked function ran; inlined SQL functions are part of the plan.'
            : ' Function times need `track_functions`, which this role may not set; showing the plan only.';
          const perRow =
            summary.perRowSubPlans.length > 0
              ? ` Per-row SubPlans: ${summary.perRowSubPlans.join(', ')}; wrap the policy's function calls in \`(select ...)\` so they run once as an InitPlan.`
              : '';
          findings.push({
            ...(summary.perRowSubPlans.length > 0
              ? { severity: 'warning' as const }
              : {}),
            message: `${qualified(table)} as ${who}: ${summary.executionMs.toFixed(2)} ms, ${plural(summary.initPlans, 'InitPlan')}. Plan: ${summary.nodes.join(' > ')}.${perRow}${helpers}`,
            target: `${qualified(table)}:explain`,
            object: tableObject(table),
          });
        } catch (cause) {
          findings.push({
            severity: 'warning',
            message: `--explain ${qualified(table)} failed: ${errorText(cause)}`,
            target: `${qualified(table)}:explain`,
          });
        }
      }
      return findings;
    },
  },
];
