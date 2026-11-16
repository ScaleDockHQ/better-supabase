import type { CarePlansSql } from "./care-plans-sql.ts";

import {
  filterAny,
  filterFlag,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";

/**
 * `page_care_plans` (ADR 1077): the care plans the caller reads, without their
 * problems, goals and actions. It runs as definer and keeps `visible`, the read
 * permission and the client check `list_care_plans` applies per row.
 */
export function carePlanPageFunction(q: CarePlansSql): string {
  const { fn, p, plans } = q;
  const key = { expr: `x.${p("id")}`, dir: "desc", type: "uuid" } as const;

  const newest = [
    { expr: `x.${p("createdAt")}`, dir: "desc", type: "timestamptz" },
    key,
  ] as const;

  const nullable = (column: string, dir: "asc" | "desc") =>
    [
      {
        expr: `coalesce(x.${p(column)}::timestamptz, ${dir === "asc" ? "'infinity'" : "'-infinity'"}::timestamptz)`,
        dir,
        type: "timestamptz",
      },
      key,
    ] as const;

  const spec = {
    name: "page_care_plans",
    from: plans,
    alias: "x",
    where: [
      q.visible("x"),
      filterAny("subjectType", `x.${p("subjectType")}`),
      filterAny("subjectId", `x.${p("subjectId")}`),
      filterAny("status", `x.${p("status")}::text`),
      `(${filterFlag("archived")} or x.${p("status")} <> 'archived')`,
      `(v_search is null or x.${p("title")} ilike v_search)`,
    ],
    keys: newest,
    sorts: {
      createdAt: newest,
      title: [
        { expr: `lower(x.${p("title")})`, dir: "asc", type: "text" },
        key,
      ],
      version: [
        { expr: `x.${p("version")}`, dir: "desc", type: "integer" },
        key,
      ],
      startsOn: nullable("startsOn", "asc"),
      reviewOn: nullable("reviewOn", "asc"),
    },
    facets: { status: `x.${p("status")}::text` },
    rowJson: q.planJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("CARE_PLAN_INVALID", message, "22023"),
  } as const;

  return `
-- The care plans the caller reads as a keyset page, newest first (ADR 1077).
-- filters is { subjectType, subjectId, status (each a value or a list),
-- archived (true adds archived plans), search (title), sort (createdAt,
-- title, version, startsOn, reviewOn), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${fn("page_care_plans")}(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_care_plans.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(spec)}
begin
  ${listBody(spec)}
end;
$$;
${userGrant(`${fn("page_care_plans")}(jsonb)`)}
`;
}
