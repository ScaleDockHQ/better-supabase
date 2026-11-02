import type { BlockSqlContext } from "./context.ts";

import { sqlIdent } from "../core/template.ts";

/** The generated column that holds a row's search vector. */
export const SEARCH_COLUMN = "search_tsv";

/**
 * A stored `tsvector` generated from `columns` of `table`, with a GIN index,
 * for a table the module creates (`@bsb search`, ADR 0198). Names come from the
 * quoted column expressions the caller passes. The text search configuration is
 * fixed to `simple`, which is immutable, so the column can be generated.
 */
export function searchColumnStatements(
  table: string,
  indexName: string,
  columns: readonly string[],
  config = "simple",
): string {
  if (columns.length === 0) {
    return "";
  }

  const document = columns
    .map((column) => `coalesce(${column}, '')`)
    .join(" || ' ' || ");

  return `
alter table ${table} add column if not exists ${SEARCH_COLUMN} tsvector generated always as (to_tsvector('${config}'::regconfig, ${document})) stored;
create index if not exists ${sqlIdent(indexName)} on ${table} using gin (${SEARCH_COLUMN});`;
}

/**
 * The search column of the logical `table`, from the logical `columns` the app
 * has, when `options.searchColumn` is on and the module creates the table.
 */
export function searchColumnSql(
  ctx: BlockSqlContext,
  table: string,
  columns: readonly string[],
): string {
  if (!ctx.flag("searchColumn", false) || !ctx.owns(table)) {
    return "";
  }

  return searchColumnStatements(
    ctx.table(table),
    `${ctx.tableName(table).name}_search_tsv_idx`,
    columns
      .filter((column) => ctx.has(table, column))
      .map((column) => ctx.col(table, column)),
  );
}
