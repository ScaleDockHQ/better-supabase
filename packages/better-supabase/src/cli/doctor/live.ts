import type { CatalogTable } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { CLI_QUERY_TAG } from "../introspect/source.ts";
import { PLATFORM_ROLES } from "./reserved-roles.ts";
import { catalogOf, exposed, qualified, tableObject } from "./shared.ts";

/** The database doctor checks, for statistics and plans. */
export interface LiveDatabase {
  readonly describe: string;
  /**
   * Runs statements one at a time on one session (false for the Management
   * API).
   */
  readonly session: boolean;
  query<R = Record<string, unknown>>(sql: string): Promise<R[]>;
}

/** What `--explain` plans, and as whom. */
export interface ExplainRequest {
  /** `customers` or `public.customers`. */
  readonly tables: readonly string[];
  /** `request.jwt.claims`; `role` picks the Postgres role (default `anon`). */
  readonly claims: Readonly<Record<string, unknown>>;
  /** `--args`: a JSON array (positional) or object (named) for a function. */
  readonly args?: unknown;
  /** `--explain-write`: tables to plan an insert and an update on. */
  readonly write?: readonly string[];
}

/**
 * Statements slower than this (ms, mean) with more calls than `SLOW_CALLS` are
 * BS209.
 */
const SLOW_MEAN_MS = 50;
const SLOW_CALLS = 1000;

/** Rows `--explain` reads, like a `list()` under Supabase's default `max_rows`. */
const EXPLAIN_LIMIT = 1000;

const escape = (name: string): string =>
  name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

export const ident = (name: string): string =>
  `"${name.replaceAll('"', '""')}"`;

export const literal = (text: string): string =>
  `'${text.replaceAll("'", "''")}'`;

const oneLine = (query: string, max = 160): string => {
  const flat = query.replaceAll(/\s+/g, " ").trim();

  return flat.length > max ? `${flat.slice(0, max - 1)}…` : flat;
};

const plural = (count: number, word: string): string =>
  `${count} ${word}${count === 1 ? "" : "s"}`;

const megabytes = (bytes: number): string =>
  `${(bytes / 1024 / 1024).toFixed(1)} MB`;

/** The schema `pg_stat_statements` lives in, when the extension is installed. */
export async function statementsView(
  db: LiveDatabase,
): Promise<string | undefined> {
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
  readonly "Node Type": string;
  readonly "Relation Name"?: string;
  readonly "Parent Relationship"?: string;
  readonly "Subplan Name"?: string;
  readonly "Actual Total Time"?: number;
  readonly "Actual Loops"?: number;
  readonly Plans?: readonly PlanNode[];
}

interface TriggerTime {
  readonly "Trigger Name": string;
  readonly Time?: number;
  readonly Calls?: number;
}

interface ExplainOutput {
  readonly Plan: PlanNode;
  readonly "Execution Time"?: number;
  readonly Triggers?: readonly TriggerTime[];
}

interface FunctionTime {
  readonly name: string;
  readonly calls: number;
  readonly selfTime: number;
  /** Runs with its owner's rights: the helpers policies call. */
  readonly definer: boolean;
}

/**
 * Function calls and self time so far in this transaction. The view can still
 * hold unflushed counts from earlier transactions, so callers diff two
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

/** Names (`schema.function`) of the security definer functions. */
async function definerFunctions(db: LiveDatabase): Promise<Set<string>> {
  const rows = await db.query<{ name: string }>(
    `select n.nspname || '.' || p.proname as name from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.prosecdef`,
  );

  return new Set(rows.map((row) => row.name));
}

/** Share of the execution time spent in security definer helpers, 0 to 100. */
function policyShare(
  functions: readonly FunctionTime[],
  executionMs: number,
): number {
  if (executionMs <= 0) {
    return 0;
  }

  const self = functions
    .filter((fn) => fn.definer)
    .reduce((sum, fn) => sum + fn.selfTime, 0);

  return Math.min(100, Math.round((self / executionMs) * 100));
}

export interface PlanSummary {
  /** `Seq Scan on customers 1.20 ms ×1`, depth first. */
  readonly nodes: readonly string[];
  readonly initPlans: number;
  /** SubPlans that ran more than once: once per row. */
  readonly perRowSubPlans: readonly string[];
  readonly executionMs: number;
}

/**
 * Node types, timings and loops of an `EXPLAIN (ANALYZE, FORMAT JSON)` plan;
 * never rows.
 */
export function summarizePlan(output: ExplainOutput): PlanSummary {
  const nodes: string[] = [];
  const perRowSubPlans: string[] = [];
  let initPlans = 0;

  const walk = (node: PlanNode): void => {
    const loops = node["Actual Loops"] ?? 1;
    const ms = (node["Actual Total Time"] ?? 0).toFixed(2);
    const on = node["Relation Name"] ? ` on ${node["Relation Name"]}` : "";
    const sub = node["Subplan Name"] ? `${node["Subplan Name"]}: ` : "";
    nodes.push(`${sub}${node["Node Type"]}${on} ${ms} ms ×${loops}`);

    if (node["Parent Relationship"] === "InitPlan") {
      initPlans += 1;
    }

    if (node["Parent Relationship"] === "SubPlan" && loops > 1) {
      perRowSubPlans.push(`${sub}${node["Node Type"]}${on} ×${loops}`);
    }

    for (const child of node.Plans ?? []) {
      walk(child);
    }
  };

  walk(output.Plan);

  return {
    nodes,
    initPlans,
    perRowSubPlans,
    executionMs: output["Execution Time"] ?? 0,
  };
}

const ROLE = /^[a-z_][a-z0-9_]*$/;

interface Explained {
  readonly summary: PlanSummary;
  readonly functions: FunctionTime[] | undefined;
  /** `EXPLAIN` reports the time of each trigger a write fired. */
  readonly triggers: readonly TriggerTime[];
}

async function explainStatement(
  db: LiveDatabase,
  statement: string,
  claims: Readonly<Record<string, unknown>>,
): Promise<Explained> {
  const role = typeof claims["role"] === "string" ? claims["role"] : "anon";

  if (!ROLE.test(role)) {
    throw new Error(`Invalid role "${role}" in the claims`);
  }

  await db.query("begin");

  try {
    await db.query(`set local statement_timeout = '30s'`);
    let tracked = true;
    await db.query("savepoint bsb_track");

    try {
      await db.query(`set local track_functions = 'all'`);
      await db.query("release savepoint bsb_track");
    } catch {
      tracked = false;
      await db.query("rollback to savepoint bsb_track");
    }

    await db.query(
      `select set_config('request.jwt.claims', ${literal(JSON.stringify(claims))}, true)`,
    );

    const before = tracked
      ? await functionTimes(db)
      : new Map<string, { calls: number; selfTime: number }>();

    await db.query(`set local role ${ident(role)}`);

    const [row] = await db.query<{ "QUERY PLAN": unknown }>(
      `explain (analyze, buffers, format json) ${statement}`,
    );

    const raw = row?.["QUERY PLAN"];

    // SAFETY: EXPLAIN (FORMAT JSON) returns an array of plans, as JSON or as text.
    const plan = (typeof raw === "string" ? JSON.parse(raw) : raw) as
      | ExplainOutput[]
      | undefined;

    if (!plan?.[0]) {
      throw new Error("EXPLAIN returned no plan");
    }

    const definers = tracked ? await definerFunctions(db) : new Set<string>();

    const functions = tracked
      ? [...(await functionTimes(db))]
          .map(([name, after]): FunctionTime => {
            const start = before.get(name);

            return {
              name,
              calls: after.calls - (start?.calls ?? 0),
              selfTime: after.selfTime - (start?.selfTime ?? 0),
              definer: definers.has(name),
            };
          })
          .filter((fn) => fn.calls > 0)
          .toSorted((a, b) => b.selfTime - a.selfTime)
      : undefined;

    return {
      summary: summarizePlan(plan[0]),
      functions,
      triggers: plan[0].Triggers ?? [],
    };
  } finally {
    await db.query("rollback");
  }
}

const explainTable = (
  db: LiveDatabase,
  table: CatalogTable,
  claims: Readonly<Record<string, unknown>>,
): Promise<Explained> =>
  explainStatement(
    db,
    `select * from ${ident(table.schema)}.${ident(table.name)} limit ${EXPLAIN_LIMIT}`,
    claims,
  );

interface ProcRow {
  readonly schema: string;
  readonly name: string;
  readonly arg_names: string[] | null;
  readonly arg_types: string[];
}

/**
 * `select * from schema.fn(...)` for a function in an exposed schema, with
 * `--args` as literals cast to the declared argument types: an array is
 * positional, an object is named.
 */
async function functionStatement(
  db: LiveDatabase,
  context: DoctorContext,
  name: string,
  args: unknown,
): Promise<string | undefined> {
  const schemas = new Set(exposed(context).map((table) => table.schema));
  const dot = name.indexOf(".");
  const schema = dot === -1 ? undefined : name.slice(0, dot);
  const bare = dot === -1 ? name : name.slice(dot + 1);

  const rows = await db.query<ProcRow>(
    `select n.nspname as schema, p.proname as name, p.proargnames as arg_names, coalesce(array(select format_type(t, null) from unnest(p.proargtypes::oid[]) as t), '{}') as arg_types from pg_proc p join pg_namespace n on n.oid = p.pronamespace where p.proname = ${literal(bare)} and p.prokind = 'f'${schema ? ` and n.nspname = ${literal(schema)}` : ""} order by p.pronargs desc`,
  );

  const proc =
    rows.find((row) => schema !== undefined || schemas.has(row.schema)) ??
    rows[0];

  if (!proc || (schema === undefined && !schemas.has(proc.schema))) {
    return undefined;
  }

  const typed = (value: unknown, type: string | undefined): string => {
    const text = typeof value === "string" ? value : JSON.stringify(value);

    return `${literal(text)}${type ? `::${type}` : ""}`;
  };

  let list = "";

  if (Array.isArray(args)) {
    list = args.map((value, i) => typed(value, proc.arg_types[i])).join(", ");
  } else if (typeof args === "object" && args !== null) {
    list = Object.entries(args)
      .map(([key, value]) => {
        const at = proc.arg_names?.indexOf(key) ?? -1;

        return `${ident(key)} => ${typed(value, at === -1 ? undefined : proc.arg_types[at])}`;
      })
      .join(", ");
  }

  return `select * from ${ident(proc.schema)}.${ident(proc.name)}(${list})`;
}

interface ColumnRow {
  readonly name: string;
  readonly type: string;
  readonly has_default: boolean;
  readonly generated: boolean;
  readonly is_key: boolean;
}

const UUID_TYPE = /^uuid$/;
const TEXT_TYPE = /^(text|character varying|citext|character)/;
const NUMBER_TYPE = /^(smallint|integer|bigint)$/;

/**
 * An insert of a copy of one row with fresh keys, and an update of one non-key
 * column, for `--explain-write`. Throws with the reason when a key has no value
 * to make up.
 */
async function writeStatements(
  db: LiveDatabase,
  table: CatalogTable,
): Promise<{ insert: string; update: string }> {
  const target = `${ident(table.schema)}.${ident(table.name)}`;

  const columns = await db.query<ColumnRow>(
    `select a.attname::text as name, format_type(a.atttypid, a.atttypmod) as type, a.atthasdef as has_default, (a.attgenerated <> '' or a.attidentity = 'a') as generated, coalesce(a.attnum = any(i.indkey), false) as is_key from pg_attribute a left join pg_index i on i.indrelid = a.attrelid and i.indisprimary where a.attrelid = ${literal(target)}::regclass and a.attnum > 0 and not a.attisdropped order by a.attnum`,
  );

  const names: string[] = [];
  const values: string[] = [];

  for (const column of columns) {
    if (column.generated) {
      continue;
    }

    const id = ident(column.name);

    if (!column.is_key) {
      names.push(id);
      values.push(`s.${id}`);
    } else if (UUID_TYPE.test(column.type)) {
      names.push(id);
      values.push("gen_random_uuid()");
    } else if (TEXT_TYPE.test(column.type)) {
      names.push(id);
      values.push(`'bsb_explain_' || gen_random_uuid()::text`);
    } else if (!(NUMBER_TYPE.test(column.type) && column.has_default)) {
      throw new Error(
        `can't make a fresh key for ${column.name} (${column.type}); use a uuid, text or defaulted integer key`,
      );
    }
  }

  const changed = columns.find((column) => !column.is_key && !column.generated);

  if (!changed) {
    throw new Error("the table has no non-key column to update");
  }

  const id = ident(changed.name);

  return {
    insert: `insert into ${target} (${names.join(", ")}) select ${values.join(", ")} from (select * from ${target} limit 1) s`,
    update: `update ${target} set ${id} = ${id} where ctid = (select ctid from ${target} limit 1)`,
  };
}

/** Trigger time per statement, as `bsb_audit 0.12 ms over 1 call`. */
const triggerText = (triggers: readonly TriggerTime[]): string =>
  triggers.length === 0
    ? "no triggers fired"
    : triggers
        .map(
          (trigger) =>
            `${trigger["Trigger Name"]} ${(trigger.Time ?? 0).toFixed(2)} ms over ${plural(trigger.Calls ?? 0, "call")}`,
        )
        .join(", ");

/** `--explain-write` for one table: an insert and an update, rolled back. */
async function explainWrite(
  db: LiveDatabase,
  table: CatalogTable,
  claims: Readonly<Record<string, unknown>>,
  who: string,
): Promise<FindingInput> {
  const label = qualified(table);

  try {
    const statements = await writeStatements(db, table);
    const parts: string[] = [];

    for (const kind of ["insert", "update"] as const) {
      const { summary, triggers } = await explainStatement(
        db,
        statements[kind],
        claims,
      );

      const fired = triggers.reduce((sum, item) => sum + (item.Time ?? 0), 0);

      parts.push(
        `${kind} ${summary.executionMs.toFixed(2)} ms, of which triggers ${fired.toFixed(2)} ms (${triggerText(triggers)})`,
      );
    }

    return {
      message: `${label} write as ${who}: ${parts.join("; ")}. Each statement ran in a rolled-back transaction on a copy of one existing row with fresh keys; the update assigns a column its own value, so triggers that only fire on a changed column don't show.`,
      target: `${label}:explain-write`,
      object: tableObject(table),
    };
  } catch (cause) {
    return {
      severity: "warning",
      message: `--explain-write ${label} failed: ${errorText(cause)}`,
      target: `${label}:explain-write`,
    };
  }
}

function resolveTable(
  context: DoctorContext,
  name: string,
): CatalogTable | undefined {
  return name.includes(".")
    ? catalogOf(context).tables.find((table) => qualified(table) === name)
    : exposed(context).find((table) => table.name === name);
}

export const LIVE_RULES: readonly Rule[] = [
  {
    code: "BS208",
    severity: "warning",
    title: "Queries spill to temporary files",
    description:
      "Sorts and hashes that exceed `work_mem` write temporary files, which is slow. Reads `pg_stat_database` and, when installed, the top statements from `pg_stat_statements`. When every statement that spilled ran as a Supabase service role (PostgREST's schema cache query as `authenticator`, Auth or Storage) or came from better-supabase's own catalog reads (`gen`, `doctor`), there is no finding.",
    async check(context) {
      const db = live(context);

      if (!db || "skipped" in db) {
        return [];
      }

      try {
        const [stats] = await db.query<{
          temp_files: number | string;
          temp_bytes: number | string;
          work_mem: string;
        }>(
          `select temp_files, temp_bytes, current_setting('work_mem') as work_mem from pg_stat_database where datname = current_database()`,
        );

        const files = Number(stats?.temp_files ?? 0);

        if (files === 0) {
          return [];
        }

        let top = "";
        const view = await statementsView(db);

        if (view) {
          const spilled = await db
            .query<{
              query: string;
              temp_blks_written: number | string;
              role: string | null;
            }>(
              `select s.query, s.temp_blks_written, r.rolname as role from ${view} s left join pg_roles r on r.oid = s.userid where s.temp_blks_written > 0 order by s.temp_blks_written desc limit 50`,
            )
            .catch(() => []);

          const statements = spilled
            .filter(
              (statement) =>
                !statement.query.startsWith(CLI_QUERY_TAG) &&
                (statement.role === null ||
                  !PLATFORM_ROLES.has(statement.role)),
            )
            .slice(0, 5);

          if (spilled.length > 0 && statements.length === 0) {
            return [];
          }

          if (statements.length > 0) {
            top = ` Top statements by temporary blocks written: ${statements
              .map(
                (statement) =>
                  `${oneLine(statement.query, 100)} (${statement.temp_blks_written} blocks)`,
              )
              .join("; ")}.`;
          }
        }

        return [
          {
            message: `${files} temporary files (${megabytes(Number(stats?.temp_bytes ?? 0))}) since the statistics were reset; work_mem is ${stats?.work_mem}. Add indexes so large sorts go away, or raise work_mem for the role that runs them.${top}`,
            target: "pg_stat_database:temp_files",
          },
        ];
      } catch (cause) {
        return [
          {
            severity: "info",
            message: `Could not read pg_stat_database (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
  {
    code: "BS209",
    severity: "warning",
    title: "Slow frequent statements",
    description: `Statements from \`pg_stat_statements\` with a mean time above ${SLOW_MEAN_MS} ms and more than ${SLOW_CALLS} calls. Runs with \`--stats\`.`,
    async check(context) {
      if (!context.stats) {
        return [];
      }

      const db = live(context);

      if (!db) {
        return [];
      }

      if ("skipped" in db) {
        return [
          { severity: "info", message: `Skipped --stats: ${db.skipped}` },
        ];
      }

      try {
        const view = await statementsView(db);

        if (!view) {
          return [
            {
              severity: "info",
              message:
                "pg_stat_statements is not installed, so --stats has nothing to read. Run `create extension pg_stat_statements with schema extensions;`.",
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
            severity: "info",
            message: `Could not read pg_stat_statements (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }
    },
  },
  {
    code: "BS225",
    severity: "info",
    title: "pg_stat_statements is not installed",
    description:
      "`pg_stat_statements` records the time and calls of each statement, which `--stats` (BS209), BS208 and the Supabase query performance report read. Without it there is no record of which queries are slow. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = live(context);

      if (!db || "skipped" in db) {
        return [];
      }

      // BS209 reports the missing extension itself when --stats runs.
      if (context.stats && context.codes?.includes("BS209")) {
        return [];
      }

      try {
        if (await statementsView(db)) {
          return [];
        }
      } catch {
        return [];
      }

      return [
        {
          message: `pg_stat_statements is not installed on the ${db.describe}, so nothing records which statements are slow. Run \`create extension if not exists pg_stat_statements with schema extensions;\` in a migration.`,
          target: "extension:pg_stat_statements",
        },
      ];
    },
  },
  {
    code: "BS212",
    severity: "info",
    title: "RLS plan for a table",
    description: `\`--explain <tables>\` runs \`EXPLAIN (ANALYZE, BUFFERS)\` on \`select * from <table> limit ${EXPLAIN_LIMIT}\` as the given claims, in a transaction that is rolled back. It reports node types, timings and loops, never rows, and warns when a policy SubPlan runs once per row.`,
    async check(context) {
      const request = context.explain;

      if (!request) {
        return [];
      }

      const writes = request.write ?? [];

      const db = live(context);

      if (!db || "skipped" in db || !db.session) {
        return [
          {
            severity: "warning",
            message: `--explain needs a direct database connection (local stack, $DATABASE_URL, $SUPABASE_DB_URL or --db-url-stdin)${db && "skipped" in db ? `: ${db.skipped}` : "."}`,
          },
        ];
      }

      const who =
        typeof request.claims["sub"] === "string"
          ? `${String(request.claims["role"] ?? "anon")} ${request.claims["sub"]}`
          : String(request.claims["role"] ?? "anon");

      const findings: FindingInput[] = [];

      for (const name of request.tables) {
        const table = resolveTable(context, name);

        let statement: string | undefined;

        if (!table) {
          try {
            statement = await functionStatement(
              db,
              context,
              name,
              request.args,
            );
          } catch (cause) {
            findings.push({
              severity: "warning",
              message: `--explain ${name} failed: ${errorText(cause)}`,
              target: `${name}:explain`,
            });
            continue;
          }
        }

        if (!table && statement === undefined) {
          findings.push({
            severity: "warning",
            message: `--explain: no table or function "${name}" in the exposed schemas; qualify names in other schemas, like better_supabase.memberships.`,
          });
          continue;
        }

        const label = table ? qualified(table) : name;

        try {
          const { summary, functions } = table
            ? await explainTable(db, table, request.claims)
            : await explainStatement(db, statement ?? "", request.claims);

          const helpers = functions
            ? functions.length > 0
              ? ` Function time: ${functions
                  .map((fn) => {
                    const self = fn.selfTime;

                    const share =
                      summary.executionMs > 0
                        ? Math.round((self / summary.executionMs) * 100)
                        : 0;

                    return `${fn.name} ${self.toFixed(2)} ms over ${plural(fn.calls, "call")} (${share}%)`;
                  })
                  .join(", ")}.`
              : " No tracked function ran; inlined SQL functions are part of the plan."
            : " Function times need `track_functions`, which this role may not set; showing the plan only.";

          const policy = functions?.some((fn) => fn.definer)
            ? ` Policy time share: ${policyShare(functions, summary.executionMs)}% in security definer helpers.`
            : "";

          const perRow =
            summary.perRowSubPlans.length > 0
              ? ` Per-row SubPlans: ${summary.perRowSubPlans.join(", ")}; wrap the policy's function calls in \`(select ...)\` so they run once as an InitPlan.`
              : "";

          findings.push({
            ...(summary.perRowSubPlans.length > 0
              ? { severity: "warning" as const }
              : {}),
            message: `${label} as ${who}: ${summary.executionMs.toFixed(2)} ms, ${plural(summary.initPlans, "InitPlan")}. Plan: ${summary.nodes.join(" > ")}.${perRow}${helpers}${policy}`,
            target: `${label}:explain`,
            ...(table ? { object: tableObject(table) } : {}),
          });
        } catch (cause) {
          findings.push({
            severity: "warning",
            message: `--explain ${label} failed: ${errorText(cause)}`,
            target: `${label}:explain`,
          });
        }
      }

      for (const name of writes) {
        const table = resolveTable(context, name);

        findings.push(
          table
            ? await explainWrite(db, table, request.claims, who)
            : {
                severity: "warning",
                message: `--explain-write: no table "${name}" in the exposed schemas; qualify names in other schemas.`,
              },
        );
      }

      return findings;
    },
  },
];
