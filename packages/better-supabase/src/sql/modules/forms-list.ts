import type { BlockSqlContext } from "../context.ts";

import { filterAny, listBody, listDeclare } from "../list-template.ts";
import { fail, SERVICE_CALLER, userGrant } from "../shared.ts";
import { OPERATIONS } from "./permissions-model.ts";

/**
 * `list_forms`: one page of an organization's forms (ADR 0749). `formJson`
 * renders one row over the alias it is given.
 */
export function formListFunction(
  ctx: BlockSqlContext,
  formJson: (row: string) => string,
): string {
  const forms = ctx.table("forms");
  const fn = (name: string): string => ctx.fn(name);
  const f = (column: string): string => ctx.col("forms", column);
  const read = ctx.permission("read", OPERATIONS["forms.read"]);

  const list = {
    name: "list_forms",
    from: forms,
    alias: "x",
    where: [
      `x.${f("tenant")} = list_forms.tenant`,
      filterAny("status", `x.${f("status")}::text`),
    ],
    keys: [
      { expr: `x.${f("createdAt")}`, dir: "desc", type: "timestamptz" },
      { expr: `x.${f("id")}`, dir: "desc", type: "uuid" },
    ],
    sorts: {
      createdAt: [
        { expr: `x.${f("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `x.${f("id")}`, dir: "desc", type: "uuid" },
      ],
      title: [
        { expr: `x.${f("title")}`, dir: "asc", type: "text" },
        { expr: `x.${f("id")}`, dir: "asc", type: "uuid" },
      ],
      key: [
        { expr: `x.${f("key")}`, dir: "asc", type: "text" },
        { expr: `x.${f("id")}`, dir: "asc", type: "uuid" },
      ],
    },
    facets: { status: `x.${f("status")}` },
    rowJson: formJson("x"),
    defaultLimit: 200,
    maxLimit: 500,
    invalid: (message: string): string =>
      fail("FORM_INVALID", message, "22023"),
  } as const;

  return `-- Newest first. filters is { status (a value or a list), sort, direction, facet,
-- count, limit, after, offset, paged, total, totalCap } (ADR 0749).
create or replace function ${fn("list_forms")}(tenant ${ctx.idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_forms.filters, '{}'::jsonb);
  ${listDeclare(list)}
begin
  if not (${SERVICE_CALLER} or ${ctx.can("tenant", "list_forms.tenant", read)}) then
    ${fail("FORM_FORBIDDEN", "not allowed to read forms")}
  end if;
  ${listBody(list)}
end;
$$;
${userGrant(`${fn("list_forms")}(${ctx.idType}, jsonb)`)}`;
}
