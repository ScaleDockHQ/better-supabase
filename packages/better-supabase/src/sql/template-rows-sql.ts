import type { SubjectConfig } from "../config/types/subjects.ts";

import { sqlIdent } from "../core/template.ts";
import { fail } from "./shared.ts";

/**
 * A table that holds template rows (ADR 0244). `column` is the physical column
 * that points at `templates`; `children` are the rows a clone copies with it.
 */
export interface TemplateRows {
  readonly column: string;
  readonly children: readonly TemplateChild[];
}

/** One child table a clone copies: `column` references the parent row. */
export interface TemplateChild {
  readonly table: string;
  readonly column: string;
}

/**
 * The template column of a subject, when the table holds template rows. A
 * string is the column; an object also names the child tables a clone copies.
 */
export function templateRowsOf(
  config: Pick<SubjectConfig, "template">,
): TemplateRows | undefined {
  const value = config.template;

  if (value === undefined) {
    return undefined;
  }

  if (typeof value === "string") {
    return { column: value, children: [] };
  }

  return { column: value.column, children: value.children ?? [] };
}

/** `alias.column is null`: the row is a live record, not a template. */
export function isLiveRow(alias: string, column: string): string {
  return `${alias}.${sqlIdent(column)} is null`;
}

/**
 * An early return for a template row, or "" when the subject has no template
 * column. The block ends in a newline so the next statement keeps its indent.
 */
export function templateTriggerReturn(
  column: string | undefined,
  value: "new" | "null",
): string {
  return column === undefined
    ? ""
    : `  if new.${sqlIdent(column)} is not null then
    return ${value};
  end if;
`;
}

/** ` and alias.template is null` when the subject holds template rows. */
export function excludeTemplates(
  config: Pick<SubjectConfig, "template">,
  alias: string,
): string {
  const column = templateRowsOf(config)?.column;

  return column === undefined
    ? ""
    : ` and ${alias}.${sqlIdent(column)} is null`;
}

/**
 * The `template` column: a uuid that points at the templates table. Unique on
 * the root table of a type, so one template owns one root row; bundle members
 * share the id and are not unique.
 */
export function templateColumnSql(
  column: string,
  templates: string,
  unique: boolean,
): string {
  return `${sqlIdent(column)} uuid${unique ? " unique" : ""} references ${templates} (id) on delete cascade`;
}

/** The column that records which template a live row was made from. */
export function sourceTemplateColumnSql(
  column: string,
  templates: string,
): string {
  return `${sqlIdent(column)} uuid references ${templates} (id) on delete set null`;
}

/**
 * A before-update trigger that refuses a change of the template column, so a
 * row never switches between a template and a live record.
 */
export function templateGuardSql(options: {
  readonly fn: string;
  readonly trigger: string;
  readonly table: string;
  readonly column: string;
  readonly hint: string;
}): string {
  const column = sqlIdent(options.column);

  return `create or replace function ${options.fn}()
returns trigger
language plpgsql
as $$
begin
  if tg_op = 'UPDATE' and new.${column} is distinct from old.${column} then
    ${fail(options.hint, "A row cannot change between a template and a live record", "23514")}
  end if;
  return new;
end;
$$;

drop trigger if exists ${options.trigger} on ${options.table};
create trigger ${options.trigger}
  before update of ${column} on ${options.table}
  for each row execute function ${options.fn}();`;
}

/**
 * The party stays required on a live row: a template may leave it null.
 * `parties` are the columns that count (any one of them).
 */
export function templatePartyCheck(
  name: string,
  template: string,
  parties: readonly string[],
): string {
  const live = parties
    .map((column) => `${sqlIdent(column)} is not null`)
    .join(" or ");

  return `constraint ${sqlIdent(name)} check (${sqlIdent(template)} is not null or ${live})`;
}

/** A partial index over the live rows, the ones lists read by default. */
export function liveRowsIndex(
  name: string,
  table: string,
  columns: string,
  template: string,
): string {
  return `create index if not exists ${sqlIdent(name)} on ${table} (${columns}) where ${sqlIdent(template)} is null;`;
}
