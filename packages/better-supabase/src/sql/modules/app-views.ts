import type {
  AppLookupConfig,
  AppRollupConfig,
  AppTableConfig,
} from "../../config/types/app-tables.ts";

import { hasComputed } from "../../config/app-computed.ts";
import { sqlIdent, sqlString } from "../../core/template.ts";
import { revokeTable } from "../shared.ts";

const SCHEMA = "public";

const qualified = (table: string): string =>
  `${sqlIdent(SCHEMA)}.${sqlIdent(table)}`;

/** The view that holds the rollups and lookups of an app table. */
export const appViewName = (table: string): string => `${table}_view`;

function rollupJoin(alias: string, rollup: AppRollupConfig): string {
  const read =
    rollup.column === undefined ? "*" : `c.${sqlIdent(rollup.column)}`;

  const value =
    rollup.aggregate === "sum"
      ? `coalesce(sum(${read}), 0)`
      : `${rollup.aggregate}(${read})`;

  const filter =
    rollup.where === undefined
      ? ""
      : ` and c.${sqlIdent(rollup.where.column)} = ${sqlString(rollup.where.equals)}`;

  return `left join lateral (select ${value} as value from ${qualified(rollup.table)} c where c.${sqlIdent(rollup.via)} = t.id${filter}) ${alias} on true`;
}

function lookupJoin(
  alias: string,
  lookup: AppLookupConfig,
  config: AppTableConfig,
): string {
  const reference = config.columns?.[lookup.via]?.references;

  if (reference === undefined || "block" in reference) {
    throw new TypeError(
      `lookup via ${lookup.via}: the column references no app table`,
    );
  }

  return `left join lateral (select r.${sqlIdent(lookup.column)} as value from ${qualified(reference.table)} r where r.id = t.${sqlIdent(lookup.via)}) ${alias} on true`;
}

/**
 * `public.<table>_view`: every column of the table, then each rollup and
 * lookup from a lateral join. `security_invoker` runs it with the caller's
 * row level security on every table it reads, so a rollup counts only the
 * rows the caller reaches. The joins also keep Postgres from treating the
 * view as updatable, so `gen` types it read-only. Dropped and created again,
 * since `t.*` fixes the column list when the view is created. Empty for a
 * table without rollups or lookups.
 */
export function appViewSql(name: string, config: AppTableConfig): string {
  if (!hasComputed(config)) {
    return "";
  }

  const view = qualified(appViewName(name));

  const joins = [
    ...Object.entries(config.rollups ?? {}).map(([column, rollup], index) => ({
      column,
      alias: `r${String(index)}`,
      sql: rollupJoin(`r${String(index)}`, rollup),
    })),
    ...Object.entries(config.lookups ?? {}).map(([column, lookup], index) => ({
      column,
      alias: `l${String(index)}`,
      sql: lookupJoin(`l${String(index)}`, lookup, config),
    })),
  ];

  const columns = [
    "t.*",
    ...joins.map(
      ({ column, alias }) => `${alias}.value as ${sqlIdent(column)}`,
    ),
  ];

  return `drop view if exists ${view};
create view ${view} with (security_invoker = true) as
select ${columns.join(",\n  ")}
from ${qualified(name)} t
  ${joins.map((join) => join.sql).join("\n  ")};
${revokeTable(view)}
grant select on ${view} to authenticated;
grant select on ${view} to service_role;
comment on view ${view} is ${sqlString(`The rollups and lookups of ${SCHEMA}.${name}, read with the caller's row level security.`)};`;
}

/**
 * The pgTAP checks of the view, run as the superuser: it exists, runs as
 * the invoker, and only `authenticated` and `service_role` read it.
 */
export function appViewChecks(name: string, config: AppTableConfig): string[] {
  if (!hasComputed(config)) {
    return [];
  }

  const view = appViewName(name);
  const label = `${SCHEMA}.${view}`;

  return [
    `select extensions.has_view('${SCHEMA}', ${sqlString(view)}, ${sqlString(`${label} exists`)});`,
    `select extensions.ok((select coalesce('security_invoker=true' = any(c.reloptions), false) from pg_catalog.pg_class c where c.oid = ${sqlString(qualified(view))}::regclass), ${sqlString(`${label} runs with the caller's row level security`)});`,
    `select extensions.table_privs_are('${SCHEMA}', ${sqlString(view)}, 'anon', array[]::text[], ${sqlString(`anon has no privileges on ${label}`)});`,
    `select extensions.table_privs_are('${SCHEMA}', ${sqlString(view)}, 'authenticated', array['SELECT'], ${sqlString(`authenticated only reads ${label}`)});`,
  ];
}

/**
 * The check run as a signed-in user who belongs to nothing: they see no
 * rows of the view of a scoped table. Empty for a table in `none` scope,
 * which every signed-in user reads.
 */
export function appViewBehaviour(
  name: string,
  config: AppTableConfig,
  scoped: boolean,
): string[] {
  if (!hasComputed(config) || !scoped) {
    return [];
  }

  const view = appViewName(name);

  return [
    `select extensions.is((select count(*)::integer from ${qualified(view)}), 0, ${sqlString(`a stranger sees no rows of ${SCHEMA}.${view}`)});`,
  ];
}
