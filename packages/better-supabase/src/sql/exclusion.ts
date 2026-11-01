import { sqlIdent, sqlString } from "../core/template.ts";

/** One element of an exclusion constraint: an expression and its operator. */
export interface ExclusionElement {
  readonly expression: string;
  readonly operator: "=" | "&&";
}

/**
 * A gist exclusion constraint on `table` (ADR 0023, ADR 0198), added once: a
 * constraint with the name `name` is left alone. `btree_gist` makes `=` work
 * next to `&&` in one index. Rows that already overlap make the statement fail,
 * so the callers keep it behind an option.
 */
export function ensureExclusion(
  table: string,
  name: string,
  elements: readonly ExclusionElement[],
  where?: string,
): string {
  const list = elements
    .map((element) => `${element.expression} with ${element.operator}`)
    .join(", ");

  return `create extension if not exists btree_gist with schema extensions;
do $$
begin
  if not exists (
    select 1 from pg_catalog.pg_constraint c
    where c.conrelid = ${sqlString(table)}::regclass and c.conname = ${sqlString(name)}
  ) then
    alter table ${table} add constraint ${sqlIdent(name)} exclude using gist (${list})${where === undefined ? "" : ` where (${where})`};
  end if;
end;
$$;`;
}
