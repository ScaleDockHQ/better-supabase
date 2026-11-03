import type { AppTableConfig } from "../../config/types/app-tables.ts";
import type { BlockSqlContext } from "../context.ts";

import { sqlIdent, sqlString } from "../../core/template.ts";

const SCHEMA = "public";

/** The table as the column group trigger needs it. */
export interface GroupTable {
  readonly name: string;
  readonly config: AppTableConfig;
  readonly ctx: BlockSqlContext;
  /** The tenant column, or undefined when the table has no scope column. */
  readonly tenant: string | undefined;
}

const target = (table: GroupTable): string =>
  `${sqlIdent(SCHEMA)}.${sqlIdent(table.name)}`;

/**
 * The `before update` trigger of `columnGroups` (ADR 0216). It raises 42501
 * when a signed-in user (`authenticated` or `anon`) changes a column of a group
 * without the group's permission in the row's tenant. The service role and the
 * table owner, and so security definer functions, are not checked. The
 * permission is read for the old row's tenant, so an update can't move the row
 * to a tenant first.
 */
export function columnGroupsSql(table: GroupTable): string {
  const groups = Object.entries(table.config.columnGroups ?? {});

  if (groups.length === 0) {
    return "";
  }

  if (table.ctx.scope.kind !== "tenant" || table.tenant === undefined) {
    throw new TypeError(
      `tables.${table.name}.columnGroups needs a table scoped per tenant, since a permission is checked in the row's tenant`,
    );
  }

  const fn = table.ctx.fn(`${table.name}_column_groups`);
  const trigger = table.ctx.trigger("column_groups");

  const branch = ([name, group]: (typeof groups)[number]): string => {
    const changed = group.columns
      .map(
        (column) =>
          `new.${sqlIdent(column)} is distinct from old.${sqlIdent(column)}`,
      )
      .join("\n      or ");

    const can = table.ctx.scope.can(
      `old.${sqlIdent(table.tenant ?? "")}`,
      sqlString(group.update),
    );

    return `  if ${changed} then
    if not ${can} then
      raise exception ${sqlString(`updating the ${name} columns of ${SCHEMA}.${table.name} needs the ${group.update} permission`)}
        using errcode = '42501';
    end if;
  end if;`;
  };

  return `create or replace function ${fn}()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if current_user not in ('authenticated', 'anon') then
    return new;
  end if;
${groups.map((entry) => branch(entry)).join("\n")}
  return new;
end;
$$;
revoke all on function ${fn}() from public, anon, authenticated;
drop trigger if exists ${trigger} on ${target(table)};
create trigger ${trigger} before update on ${target(table)}
  for each row execute function ${fn}();`;
}

/** PgTAP checks that the column group trigger exists; empty without groups. */
export function columnGroupChecks(table: GroupTable): readonly string[] {
  if (Object.keys(table.config.columnGroups ?? {}).length === 0) {
    return [];
  }

  return [
    `select extensions.has_trigger('${SCHEMA}'::name, ${sqlString(table.name)}::name, ${sqlString(table.ctx.trigger("column_groups").replaceAll('"', ""))}::name, ${sqlString(`${SCHEMA}.${table.name} checks the permission of its column groups`)});`,
  ];
}
