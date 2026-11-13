import type { CatalogTable, CatalogTrigger } from "../introspect/types.ts";
import type { DoctorContext, FindingInput, Rule, TextFile } from "./rules.ts";

import { ownerOf, splitStatements } from "../../sql/index.ts";
import { errorText } from "../core/errors.ts";
import { writtenByBlocks } from "../sql-layout.ts";
import { EDGE_FUNCTION_RULES } from "./edge-functions.ts";
import { statementsView } from "./live.ts";
import { OVERRIDE_RULES } from "./overrides.ts";
import { catalogOf, policyObject, qualified, tableObject } from "./shared.ts";
import { TENANT_TRIGGER_RULES } from "./tenant-triggers.ts";

/** Row-level `bsb_*` triggers on one table before BS387 reports it. */
const TRIGGER_PILE_UP = 6;

const SYSTEM_SCHEMAS: ReadonlySet<string> = new Set([
  "auth",
  "extensions",
  "pg_catalog",
  "information_schema",
  "storage",
  "realtime",
  "vault",
]);

const escape = (name: string): string =>
  name.replaceAll(/[.*+?^${}()|[\]\\]/g, "\\$&");

/** The schema files of the project, not its migrations or data files. */
const sqlTexts = (context: DoctorContext): readonly TextFile[] =>
  context.sqlFiles ?? [];

/** The app's own schema files: no migration, and no file the blocks wrote. */
const appSqlTexts = (context: DoctorContext): readonly TextFile[] =>
  sqlTexts(context).filter(
    (file) => !file.path.includes("/migrations/") && !writtenByBlocks(file),
  );

/**
 * Whether a policy expression calls `schema.name` outside a `(select ...)`, the
 * form Postgres prints for an InitPlan.
 */
function callsPerRow(
  expression: string,
  name: string,
  table: string,
  columns: ReadonlySet<string>,
  fallbackAllowed = false,
): boolean {
  const call = new RegExp(
    String.raw`(?<![\w.])(?<!select\s+)(?:"?\w+"?\.)?"?${escape(name)}"?\s*\(`,
    "gi",
  );

  const wholeRow = new RegExp(
    String.raw`(?:^|,)\s*(?:"?\w+"?\.)?"?${escape(table)}"?(?:\.\*)?\s*(?:,|$)`,
    "i",
  );

  return [...expression.matchAll(call)].some((match) => {
    const before = expression.slice(0, match.index);
    const args = argumentsAt(expression, match.index + match[0].length);

    if (fallbackAllowed && AFTER_SET.test(before) && wholeRow.test(args)) {
      return false;
    }

    return (
      !/(?:\b(?:from|join)\s+(?:\(\s*)*(?:lateral\s+)?|,\s*lateral\s+)$/i.test(
        before,
      ) || readsRow(args, table, columns)
    );
  });
}

const AFTER_SET =
  /\bin\s*\(\s*select\b[^()]*(?:\([^()]*\)[^()]*)*\)\s*\)*\s*or\s*$/i;

function argumentsAt(expression: string, start: number): string {
  let depth = 1;
  let quoted = false;
  let text = "";

  for (let at = start; at < expression.length && depth > 0; at += 1) {
    const char = expression.charAt(at);

    if (char === "'") {
      quoted = !quoted;
    } else if (!quoted) {
      depth += char === "(" ? 1 : char === ")" ? -1 : 0;
      text += depth > 0 ? char : "";
    }
  }

  return text;
}

const readsRow = (
  args: string,
  table: string,
  columns: ReadonlySet<string>,
): boolean =>
  args
    .replaceAll(/::\s*"?\w+"?/g, "")
    .replaceAll(/"?(\w+)"?\s*\.\s*"?\w+"?/g, (qualified, owner: string) =>
      owner.toLowerCase() === table.toLowerCase() ? qualified : "",
    )
    .split(/\W+/)
    .some((word) => columns.has(word.toLowerCase()));

/** The body of the first `create function` of `name` among the SQL files. */
function functionSource(
  files: readonly TextFile[],
  name: string,
): string | undefined {
  const pattern = new RegExp(
    String.raw`^create\s+(?:or\s+replace\s+)?function\s+(?:"?\w+"?\.)?"?${escape(name)}"?\s*\(`,
    "i",
  );

  for (const file of files) {
    for (const statement of splitStatements(file.text)) {
      if (pattern.test(statement.text.replaceAll(/\s+/g, " "))) {
        return statement.text;
      }
    }
  }

  return undefined;
}

const lastPart = (name: string): string =>
  name.slice(name.lastIndexOf(".") + 1);

/** The `schema.table` of every subject an import can write to. */
function importTables(context: DoctorContext): ReadonlySet<string> {
  const imports = context.config.blocks["imports"];

  if (imports === undefined) {
    return new Set();
  }

  const subjects = context.config.subjects;
  const targets = imports.options?.["targets"];

  const entries: unknown[] =
    typeof targets === "object" && targets !== null
      ? Object.values(targets)
      : [];

  const types = entries.flatMap((target) => {
    const type =
      typeof target === "object" && target !== null && "subjectType" in target
        ? target.subjectType
        : undefined;

    return typeof type === "string" ? [type] : [];
  });

  const named = types.length === 0 ? Object.keys(subjects) : types;

  return new Set(
    named.flatMap((type) => {
      const table = subjects[type]?.table;

      return table === undefined
        ? []
        : [table.includes(".") ? table : `public.${table}`];
    }),
  );
}

const isSearchTrigger = (trigger: CatalogTrigger): boolean =>
  trigger.name.startsWith("bsb_search_");

const rowTriggers = (table: CatalogTable): readonly CatalogTrigger[] =>
  table.triggers.filter(
    (trigger) => trigger.level === "row" && trigger.name.startsWith("bsb_"),
  );

/**
 * An index whose columns start with all of another's, on the same method and
 * predicate, so the shorter one only costs writes.
 */
function redundantIndexes(
  table: CatalogTable,
): readonly { readonly index: string; readonly covers: string }[] {
  const usable = table.indexes.filter(
    (index) =>
      (index.method ?? "btree") === "btree" &&
      index.columns.length > 0 &&
      index.columns.every((column) => column !== "" && !column.includes("(")),
  );

  const found: { index: string; covers: string }[] = [];

  for (const small of usable) {
    if (small.primary || small.unique) {
      continue;
    }

    const cover = usable.find(
      (big) =>
        big !== small &&
        (big.predicate ?? null) === (small.predicate ?? null) &&
        big.columns.length >= small.columns.length &&
        small.columns.every((column, at) => big.columns[at] === column) &&
        // Two identical indexes: keep the one that sorts first.
        (big.columns.length > small.columns.length ||
          big.unique ||
          big.primary ||
          big.name < small.name),
    );

    if (cover !== undefined) {
      found.push({ index: small.name, covers: cover.name });
    }
  }

  return found;
}

const ANY_PARAMETER =
  /\b([a-z_][\w]*(?:\.[a-z_][\w]*)?)\s+is\s+null\s+or\s+[\w."]+\s*=\s*any\s*\(\s*\1\s*\)/gi;

const SEARCH_TAG = /@bsb\s+search\b[^\S\n]*([^\n]*)/;

/**
 * The columns a table's search option reads: those the `@bsb search` tag names,
 * else every text column. Absent for a table without the option (no tag and no
 * `search_tsv` column).
 */
function searchedColumns(table: CatalogTable): readonly string[] | undefined {
  const tag = SEARCH_TAG.exec(table.comment ?? "");

  if (tag === null && !table.columns.some((c) => c.name === "search_tsv")) {
    return undefined;
  }

  const named = (tag?.[1] ?? "").split(/[\s,]+/).filter((name) => name !== "");

  return named.length > 0
    ? named
    : table.columns
        .filter((column) => column.udt === "text" && !column.isArray)
        .map((column) => column.name);
}

/** The share of `statement_timeout` a batch's mean time may use. */
const IMPORT_TIMEOUT_SHARE = 0.5;

const DURATION = /^(\d+(?:\.\d+)?)\s*(ms|s|min|h|d)?$/;

const UNIT_MS: Readonly<Record<string, number>> = {
  ms: 1,
  s: 1000,
  min: 60_000,
  h: 3_600_000,
  d: 86_400_000,
};

/** A Postgres duration setting in milliseconds; `undefined` for 0 (no limit). */
function durationMs(text: string): number | undefined {
  const match = DURATION.exec(text.trim());

  if (match === null) {
    return undefined;
  }

  const value = Number(match[1]) * (UNIT_MS[match[2] ?? "ms"] ?? 1);

  return value > 0 ? value : undefined;
}

/** Scale checks on the catalog and the app's SQL (ADR 0500). */
const SCALE_CHECKS: readonly Rule[] = [
  {
    code: "BS386",
    severity: "warning",
    title:
      "A policy calls a volatile, PL/pgSQL or non-inlinable function per row",
    description:
      "A policy that calls a volatile function, or one written in PL/pgSQL, outside `(select ...)` runs it once for every row the statement reads, and a volatile function can't be hoisted or folded. A 100,000 row list then costs 100,000 calls. Wrap the call in `(select fn(...))` so Postgres evaluates it once per statement, or replace a per-row check with a set helper such as `tenant_id in (select tenant_ids_with('key'))`. A helper that is called inside `(select ...)` is accepted even when it is volatile, and so is a set helper in the `from` of a subquery whose arguments read no column of the row, such as `id in (select t.id from thread_ids('key') as t(id))`, because Postgres calls it once and rescans its result. In a select policy a function that is `security definer` or has a `set` clause counts too, even when it is a stable SQL function, because Postgres never inlines it, so `can_note(notes, 'read')` runs once per row. Such a call that passes the whole row is accepted as the `or` fallback after a set check, as in `id in (select note_ids('read')) or can_note(notes, 'read')`, because it then runs only for rows outside the set, such as a row the statement itself inserted. Policies named `bsb_*` belong to a block module and are left to `upgrade`.",
    check(context) {
      const catalog = catalogOf(context);

      const functions = context.snapshot.extras.functions ?? [];

      return catalog.tables.flatMap((table) =>
        table.policies.flatMap((policy): FindingInput[] => {
          // The blocks' own policies (`bsb_*`) change with the module, not by
          // hand: the set-based forms ship in `upgrade`.
          if (policy.name.startsWith("bsb_")) {
            return [];
          }

          const expressions = [policy.using, policy.check].filter(
            (text): text is string => text !== null,
          );

          const columns = new Set(
            table.columns.map((column) => column.name.toLowerCase()),
          );

          return (policy.functions ?? []).flatMap((called) => {
            const schema = called.slice(0, called.indexOf("."));
            const name = lastPart(called);

            if (SYSTEM_SCHEMAS.has(schema)) {
              return [];
            }

            const overloads = functions.filter(
              (candidate) =>
                candidate.schema === schema && candidate.name === name,
            );

            const heavy = overloads.some(
              (candidate) =>
                candidate.volatility === "volatile" ||
                candidate.language === "plpgsql",
            );

            const opaque =
              (policy.command === "select" || policy.command === "all") &&
              overloads.some(
                (candidate) =>
                  candidate.securityDefiner ||
                  Object.keys(candidate.settings).length > 0,
              );

            const perRow =
              (heavy &&
                expressions.some((text) =>
                  callsPerRow(text, name, table.name, columns),
                )) ||
              (opaque &&
                expressions.some((text) =>
                  callsPerRow(text, name, table.name, columns, true),
                ));

            if (!perRow) {
              return [];
            }

            return [
              {
                message: `${qualified(table)}: the policy ${policy.name} calls ${called}() once per row. Write (select ${called}(...)) so it runs once per statement, or use a set helper.`,
                target: `${qualified(table)}:${policy.name}`,
                object: policyObject(table, policy),
              },
            ];
          });
        }),
      );
    },
  },
  {
    code: "BS387",
    severity: "info",
    title: "Many row-level triggers on one table",
    description: `Every row-level trigger runs once per row a statement writes, so a table with ${TRIGGER_PILE_UP} or more \`bsb_*\` row triggers (search, audit, events, totals and the rest) multiplies the cost of each import or bulk update. Turn on the statement-level form where a block offers one (\`audit.statement\`), skip the triggers an import doesn't need, or split the table.`,
    check: (context) =>
      catalogOf(context)
        .tables.filter(
          (table) =>
            !SYSTEM_SCHEMAS.has(table.schema) &&
            rowTriggers(table).length >= TRIGGER_PILE_UP,
        )
        .map((table): FindingInput => ({
          message: `${qualified(table)} has ${rowTriggers(table).length} row-level bsb_* triggers (${rowTriggers(
            table,
          )
            .map((trigger) => trigger.name)
            .join(
              ", ",
            )}), so each row written runs all of them. Use statement-level triggers where a block has the option.`,
          target: qualified(table),
          object: tableObject(table),
        })),
  },
  {
    code: "BS388",
    severity: "warning",
    title: "A search trigger on an import target has no import guard",
    description:
      "An import writes thousands of rows in one transaction. A search trigger without the import guard (`better_supabase.import_run() is not null`, or the module's `search_enqueue`, which defers the refresh) rebuilds the search entry after every row instead of once per batch. Run `better-supabase upgrade` so the search module skips per-row refreshes while an import runs. Doctor looks for the guard in the trigger function's source in the schema files, so a function it can't find is left alone.",
    check(context) {
      const tables = importTables(context);

      if (tables.size === 0) {
        return [];
      }

      return catalogOf(context)
        .tables.filter((table) => tables.has(qualified(table)))
        .flatMap((table) =>
          table.triggers.filter(isSearchTrigger).flatMap((trigger) => {
            const source = functionSource(
              sqlTexts(context),
              lastPart(trigger.function),
            );

            // The search module's trigger functions call `search_enqueue` (row)
            // or `search_enqueue_many` (statement), which defer the refresh to
            // the end of the transaction while an import runs.
            if (
              source === undefined ||
              /import_run\s*\(\s*\)|search_enqueue(?:_many)?"?\s*\(/i.test(
                source,
              )
            ) {
              return [];
            }

            return [
              {
                message: `${qualified(table)}: the trigger ${trigger.name} calls ${trigger.function} on every row, and it doesn't check import_run(), so an import refreshes the search entry once per row. Run \`better-supabase upgrade\`.`,
                target: `${qualified(table)}:${trigger.name}`,
                object: tableObject(table),
              } satisfies FindingInput,
            ];
          }),
        );
    },
  },
  {
    code: "BS389",
    severity: "info",
    title: "The audit log has no scheduled purge",
    description:
      "`better_supabase.audit_events` grows with every audited write, and nothing deletes rows until something calls `better_supabase.purge_audit_log()`. Schedule it nightly with pg_cron (`select cron.schedule('purge-audit', '30 3 * * *', 'select better_supabase.purge_audit_log()')`) or from the jobs drain route. Doctor accepts a mention of `purge_audit_log` or `purgeAuditLog` in the schema files, the seeds, the app sources or a pg_cron job, and skips the rule when the project has no audit table.",
    async check(context) {
      const hasLog = catalogOf(context).tables.some(
        (table) =>
          table.schema === "better_supabase" && table.name === "audit_events",
      );

      if (!hasLog) {
        return [];
      }

      const texts = [
        ...(context.sqlFiles ?? []),
        ...(context.seedFiles ?? []),
        ...(context.dataFiles ?? []),
        ...context.sources,
      ];

      if (
        texts.some(
          (file) =>
            /purge_?audit_?log/i.test(file.text) &&
            // A block module declares the function; only a call counts.
            ownerOf(file.path, file.text).kind === "app",
        )
      ) {
        return [];
      }

      const db = context.database;

      if (db !== undefined && !("skipped" in db)) {
        try {
          const jobs = await db.query<{ n: number | string }>(
            `select count(*) as n from cron.job where command ilike '%purge_audit_log%'`,
          );

          if (Number(jobs[0]?.n ?? 0) > 0) {
            return [];
          }
        } catch {
          // No pg_cron: nothing schedules it from the database.
        }
      }

      return [
        {
          message:
            "better_supabase.audit_events has no scheduled purge, so the audit log only grows. Schedule `select better_supabase.purge_audit_log()` nightly with pg_cron or the jobs drain route.",
          target: "better_supabase.audit_events",
        },
      ];
    },
  },
  {
    code: "BS390",
    severity: "info",
    title: "A redundant index",
    description:
      "A non-unique btree index whose columns are the start of another index on the same table (same predicate) is redundant: the longer index answers every query the shorter one does, and the shorter one only slows writes and uses space. Drop it. Primary keys, unique indexes and expression indexes are left out.",
    check: (context) =>
      catalogOf(context)
        .tables.filter((table) => !SYSTEM_SCHEMAS.has(table.schema))
        .flatMap((table) =>
          redundantIndexes(table).map(({ index, covers }): FindingInput => ({
            message: `${qualified(table)}: the index ${index} is covered by ${covers}. Run \`drop index ${table.schema}.${index};\`.`,
            target: `${qualified(table)}:${index}`,
            object: tableObject(table),
          })),
        ),
  },
  {
    code: "BS391",
    severity: "info",
    title: "A parameter that is null or matched with any()",
    description:
      "`param is null or col = any(param)` in a function can't use an index on `col` when Postgres caches a generic plan, because it can't know which branch runs. Build the filter in the branch that needs it (two statements, or `case when param is null then ... end` around a subquery), or default the parameter to every value. A PL/pgSQL function that sets `plan_cache_mode = force_custom_plan` folds the null parameter, so it is accepted. Doctor reads the functions in the app's schema files, not the block modules'.",
    check: (context) =>
      sqlTexts(context)
        .filter(
          (file) =>
            !file.path.includes("migrations/") &&
            ownerOf(file.path, file.text).kind === "app",
        )
        .flatMap((file) =>
          splitStatements(file.text)
            .filter(
              (statement) =>
                /^create\s+(?:or\s+replace\s+)?function\b/i.test(
                  statement.text,
                ) && !/\bplan_cache_mode\b/i.test(statement.text),
            )
            .flatMap((statement): FindingInput[] =>
              [...statement.text.matchAll(ANY_PARAMETER)].map((match) => ({
                message: `${file.path}:${statement.line} filters with \`${match[0].replaceAll(/\s+/g, " ")}\`, which stops the planner from using an index on that column. Split the statement by whether the parameter is null, or set plan_cache_mode = force_custom_plan on a PL/pgSQL function.`,
                target: `${file.path}:${statement.line}`,
                location: { file: file.path, line: statement.line },
              })),
            ),
        ),
  },
  {
    code: "BS392",
    severity: "info",
    title: "A searched table has no trigram or sort index",
    description:
      "A table with the search option (`@bsb search`, or a `search_tsv` column) has a GIN index on the tsvector, which only serves full-text `@@` queries. A list that matches with `ilike '%text%'` needs a GIN trigram index (`gin (col gin_trgm_ops)`) on the searched column, and a list that sorts by time needs a btree index that starts with the tenant column and ends in `created_at` or `updated_at`. Without them a search or the newest-first page reads the whole table. Add the indexes in the schema file. Doctor looks for a GIN or GiST index on a searched text column, and a btree index that contains the time column.",
    check: (context) =>
      catalogOf(context).tables.flatMap((table): FindingInput[] => {
        const columns = searchedColumns(table);

        if (columns === undefined || SYSTEM_SCHEMAS.has(table.schema)) {
          return [];
        }

        const findings: FindingInput[] = [];

        const trigram = table.indexes.some(
          (index) =>
            (index.method === "gin" || index.method === "gist") &&
            index.columns.some((column) => columns.includes(column)),
        );

        if (columns.length > 0 && !trigram) {
          findings.push({
            message: `${qualified(table)} has the search option, but no GIN or GiST index on ${columns.join(", ")}, so \`ilike '%text%'\` reads every row. Add \`create index on ${qualified(table)} using gin (${columns[0] ?? "<column>"} gin_trgm_ops);\`.`,
            target: `${qualified(table)}:search`,
            object: tableObject(table),
          });
        }

        const time = table.columns.find(
          (column) =>
            column.name === "created_at" || column.name === "updated_at",
        );

        if (
          time !== undefined &&
          !table.indexes.some(
            (index) =>
              (index.method ?? "btree") === "btree" &&
              !index.primary &&
              index.columns.includes(time.name),
          )
        ) {
          findings.push({
            message: `${qualified(table)} has the search option, but no btree index that contains ${time.name}, so the newest-first page sorts every match. Add an index on (tenant column, ${time.name} desc).`,
            target: `${qualified(table)}:sort`,
            object: tableObject(table),
          });
        }

        return findings;
      }),
  },
  {
    code: "BS393",
    severity: "warning",
    title: "Import batches run close to the statement timeout",
    description: `The mean time of \`import_upsert_batch\` in \`pg_stat_statements\` is above ${String(IMPORT_TIMEOUT_SHARE * 100)}% of the \`statement_timeout\` of the service role (or the authenticator, or the server). A batch near the limit fails when the table grows or another job holds locks. Send smaller batches, or raise the role's timeout for imports. Runs with \`--stats\`.`,
    async check(context) {
      const db = context.database;

      if (!context.stats || db === undefined || "skipped" in db) {
        return [];
      }

      try {
        const view = await statementsView(db);

        if (view === undefined) {
          return [];
        }

        const batches = await db.query<{
          queryid: string;
          calls: number | string;
          mean_exec_time: number | string;
        }>(
          `select queryid::text as queryid, calls, mean_exec_time from ${view} where query ilike '%import_upsert_batch%' and query not ilike '%pg_stat_statements%' and calls >= 3 order by mean_exec_time desc limit 5`,
        );

        if (batches.length === 0) {
          return [];
        }

        const [role] = await db.query<{ timeout: string | null }>(
          `select coalesce(
  (select split_part(c, '=', 2) from pg_catalog.pg_db_role_setting s cross join unnest(s.setconfig) c join pg_catalog.pg_roles r on r.oid = s.setrole where c like 'statement_timeout=%' and r.rolname = 'service_role'),
  (select split_part(c, '=', 2) from pg_catalog.pg_db_role_setting s cross join unnest(s.setconfig) c join pg_catalog.pg_roles r on r.oid = s.setrole where c like 'statement_timeout=%' and r.rolname = 'authenticator'),
  current_setting('statement_timeout')
) as timeout`,
        );

        const limit = durationMs(role?.timeout ?? "");

        if (limit === undefined) {
          return [];
        }

        return batches
          .filter(
            (batch) =>
              Number(batch.mean_exec_time) > limit * IMPORT_TIMEOUT_SHARE,
          )
          .map((batch): FindingInput => ({
            message: `import_upsert_batch averages ${(Number(batch.mean_exec_time) / 1000).toFixed(1)} s over ${String(batch.calls)} calls, more than ${String(IMPORT_TIMEOUT_SHARE * 100)}% of the ${String(limit / 1000)} s statement_timeout. Send smaller batches or raise the timeout for the import role.`,
            target: `pg_stat_statements:${batch.queryid}`,
          }));
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
    code: "BS628",
    severity: "warning",
    title: "A list cursor has no matching index",
    description:
      "A list function orders or continues by created_at and id, and the same file has no btree index that contains both columns. The cursor then sorts the tenant. Add an index on (tenant, created_at, id) in the same direction as the order.",
    check(context) {
      return appSqlTexts(context).flatMap((file) => {
        const indexes = file.text.toLowerCase();
        const findings: FindingInput[] = [];

        for (const statement of splitStatements(file.text)) {
          const flat = statement.text.replaceAll(/\s+/g, " ");

          const name =
            /create\s+(?:or\s+replace\s+)?function\s+[\w."]+\.(list_\w+)/i.exec(
              flat,
            );

          if (!name?.[1]) {
            continue;
          }

          const usesCursor =
            /order by [^;]*created_at[^;]*\bid\b/i.test(flat) ||
            /\(\s*[\w.]+\s*,\s*[\w.]+\s*\)\s*</.test(flat);

          if (!usesCursor) {
            continue;
          }

          const indexed =
            /create\s+(?:unique\s+)?index[\s\S]*created_at[\s\S]*\bid\b/i.test(
              indexes,
            );

          if (!indexed) {
            findings.push({
              message: `${name[1]} pages by created_at and id, and ${file.path} has no index that contains both.`,
              target: file.path,
              location: { file: file.path, line: statement.line },
            });
          }
        }

        return findings;
      });
    },
  },
];

/** The scale, override, Edge Function and tenant trigger rules. */
export const SCALE_RULES: readonly Rule[] = [
  ...SCALE_CHECKS,
  ...OVERRIDE_RULES,
  ...EDGE_FUNCTION_RULES,
  ...TENANT_TRIGGER_RULES,
];
