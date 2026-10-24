import type { FindingInput, Rule } from "./rules.ts";

import { errorText } from "../core/errors.ts";
import { PLATFORM_SCHEMAS } from "../in-stack-diff.ts";
import { ident as sqlIdent, literal as sqlString } from "./live.ts";
import { scopeCheckName, scopedAppTables } from "./app-table-scope.ts";

interface NotValidCheck {
  readonly schema: string;
  readonly table: string;
  readonly name: string;
  readonly expression: string;
}

/** `(organization_id IS NOT NULL)` as `organization_id`. */
const NOT_NULL = /^\(*\s*("(?:[^"]|"")+"|[\w$]+)\s+is\s+not\s+null\s*\)*$/iu;

const notNullColumn = (expression: string): string | undefined =>
  NOT_NULL.exec(expression)?.[1]?.replace(/^"(.*)"$/su, "$1");

/**
 * Lifts the statement timeout of the introspection connection for one
 * statement, since a validate scans the whole table.
 */
const untimed = (sql: string): string =>
  `begin; set local statement_timeout = 0; ${sql} commit;`;

export const NOT_VALID_RULES: readonly Rule[] = [
  {
    code: "BS236",
    severity: "info",
    title: "Not valid check ready to validate",
    description:
      "A check constraint was added `not valid`, the expand step for a column that existing rows don't fill yet, and no row fails it any more. `doctor --fix` runs `alter table ... validate constraint`, which scans the table without blocking writes. After that, `set not null` on the column needs no scan. A check that rows still fail is reported as info, with the `db backfill` command for a not-null check; BS238 reports the scope column of an enriched app table instead. Needs a database; saved snapshots skip it.",
    async check(context) {
      const db = context.database;

      if (!db || "skipped" in db) {
        return [];
      }

      let checks: NotValidCheck[];

      try {
        checks = await db.query<NotValidCheck>(
          `select n.nspname as schema, t.relname as table, c.conname as name, pg_get_expr(c.conbin, c.conrelid) as expression
from pg_catalog.pg_constraint c
join pg_catalog.pg_class t on t.oid = c.conrelid
join pg_catalog.pg_namespace n on n.oid = t.relnamespace
where c.contype = 'c' and not c.convalidated and t.relkind in ('r', 'p')
  and n.nspname not like 'pg\\_%'
  and n.nspname not in (${[...PLATFORM_SCHEMAS].map(sqlString).join(", ")})
order by 1, 2, 3`,
        );
      } catch (cause) {
        return [
          {
            message: `Could not read the not valid checks (${db.describe}): ${errorText(cause)}`,
          },
        ];
      }

      const findings: FindingInput[] = [];

      // BS238 reports these with the rows they leave without an owner.
      const owned = new Set(
        context.codes?.includes("BS238") === true
          ? scopedAppTables(context)
              .filter((table) => table.enriched)
              .map((table) => `public.${table.name}:${scopeCheckName(table)}`)
          : [],
      );

      for (const check of checks) {
        const table = `${sqlIdent(check.schema)}.${sqlIdent(check.table)}`;
        const where = `${check.schema}.${check.table}`;
        const target = `${where}:${check.name}`;

        const object = {
          kind: "table" as const,
          schema: check.schema,
          name: check.table,
        };

        const column = notNullColumn(check.expression);

        let failing: boolean;

        try {
          const [row] = await db.query<{ failing: boolean }>(
            `select exists (select 1 from ${table} where not (${check.expression})) as failing`,
          );

          failing = row?.failing === true;
        } catch (cause) {
          findings.push({
            message: `Could not check ${check.name} on ${where}: ${errorText(cause)}`,
            target,
            object,
          });
          continue;
        }

        if (failing) {
          if (owned.has(target)) {
            continue;
          }

          findings.push({
            message: `${where} has the not valid check ${check.name} (${check.expression}), and rows still fail it.${
              column === undefined
                ? " Fix those rows, then run `better-supabase doctor --fix`."
                : ` Fill ${column} with \`better-supabase db backfill ${check.schema === "public" ? "" : `${check.schema}.`}${check.table}.${column} --from <table.column> via <column>\` (or --value), then run \`better-supabase doctor --fix\`.`
            }`,
            target,
            object,
          });
          continue;
        }

        findings.push({
          message: `${where} has the not valid check ${check.name} (${check.expression}), and no row fails it. Run \`better-supabase doctor --fix\` to validate it${
            column === undefined
              ? "."
              : `; then \`alter table ${table} alter column ${sqlIdent(column)} set not null\` needs no scan.`
          }`,
          target,
          object,
          fix: untimed(
            `alter table ${table} validate constraint ${sqlIdent(check.name)};`,
          ),
        });
      }

      return findings;
    },
  },
];
