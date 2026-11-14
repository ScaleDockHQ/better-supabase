import {
  filterAny,
  filterFirst,
  listBody,
  listDeclare,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";

/** What the deadlines functions share with their page and get reads. */
export interface DeadlinePageKit {
  /** The caller's read check on a tenant expression. */
  readonly allowed: (tenant: string) => string;
  readonly d: (column: string) => string;
  readonly deadlines: string;
  readonly fn: (name: string) => string;
  readonly idType: string;
  readonly json: (row: string) => string;
  readonly missing: string;
}

/** `page_deadlines` and `get_deadline` (ADR 0749, 0949). */
export function deadlinePageSql(kit: DeadlinePageKit): string {
  const { allowed, d, deadlines, fn, idType, json, missing } = kit;

  const dueKeys = [
    {
      expr: `coalesce(z.${d("dueOn")}, 'infinity'::date)`,
      dir: "asc",
      type: "date",
    },
    { expr: `z.${d("createdAt")}`, dir: "asc", type: "timestamptz" },
    { expr: `z.${d("id")}`, dir: "asc", type: "uuid" },
  ] as const;

  const pageList = {
    name: "page_deadlines",
    from: deadlines,
    alias: "z",
    where: [
      `z.${d("tenant")} = page_deadlines.tenant`,
      filterAny("subjectType", `z.${d("subjectType")}`),
      filterAny("subjectId", `z.${d("subjectId")}`),
      filterAny("groupKey", `z.${d("groupKey")}`),
      filterAny("period", `z.${d("period")}`),
      filterAny("state", `z.${d("state")}::text`),
      filterAny("result", `z.${d("result")}::text`),
      filterAny("provisional", `z.${d("provisional")}::text`),
      `(v_before is null or z.${d("dueOn")} < v_before)`,
    ],
    keys: dueKeys,
    sorts: {
      dueOn: dueKeys,
      createdAt: [
        { expr: `z.${d("createdAt")}`, dir: "desc", type: "timestamptz" },
        { expr: `z.${d("id")}`, dir: "desc", type: "uuid" },
      ],
    },
    facets: {
      state: `z.${d("state")}::text`,
      result: `z.${d("result")}::text`,
      groupKey: `z.${d("groupKey")}`,
    },
    rowJson: json("z"),
    invalid: (message: string): string =>
      fail("DEADLINE_INVALID", message, "22023"),
  } as const;

  return `-- An organization's deadlines as a keyset page (ADR 0749, 0949), soonest first.
-- Security invoker, as list_deadlines is. filters is { subjectType, subjectId,
-- groupKey, period, state, result, provisional (each a value or a list of
-- them), dueBefore (a date), sort, direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${fn("page_deadlines")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_deadlines.filters, '{}'::jsonb);
  v_before date;
  ${listDeclare(pageList)}
begin
  if not ${allowed("page_deadlines.tenant")} then
    ${fail("DEADLINE_FORBIDDEN", "not allowed to read deadlines")}
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    ${fail("DEADLINE_INVALID", "filters must be an object", "22023")}
  end if;
  begin
    v_before := ${filterFirst("dueBefore")}::date;
  exception when others then
    ${fail("DEADLINE_INVALID", "dueBefore must be a date", "22023")}
  end;
  ${listBody(pageList)}
end;
$$;
${userGrant(`${fn("page_deadlines")}(${idType}, jsonb)`)}

-- One deadline by id. Security invoker: the read policy decides what it sees.
create or replace function ${fn("get_deadline")}(deadline_id uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${deadlines};
begin
  select * into v_row from ${deadlines} x where x.${d("id")} = get_deadline.deadline_id;
  if not found then
    ${missing}
  end if;
  return ${json("v_row")};
end;
$$;
${userGrant(`${fn("get_deadline")}(uuid)`)}
`;
}
