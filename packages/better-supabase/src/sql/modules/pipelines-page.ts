import type { Names } from "./pipelines-bindings.ts";

import {
  filterAny,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { columnsObject, fail, userGrant } from "../shared.ts";

/**
 * `page_pipelines` and `get_pipeline` (ADR 1077): the tenant's active pipelines
 * as a keyset page, and one pipeline by id. Both return the row the array
 * `list_pipelines` returns, with its active stages in board order.
 */
export function pipelinePageFunctions(idType: string, names: Names): string {
  const { fn, t, c } = names;
  const p = (column: string): string => c("pipelines", column);
  const s = (column: string): string => c("stages", column);

  const extras =
    names.extras.length === 0
      ? ""
      : ` || jsonb_build_object('fields', ${columnsObject(
          "x",
          names.extras.map((extra) => extra.name),
        )})`;

  const rowJson = `${names.json("pipelines", "x")}${extras} || jsonb_build_object('stages', coalesce((
      select jsonb_agg(${names.json("stages", "st")} order by st.${s("rank")} collate "C")
      from ${t("stages")} st where st.${s("pipeline")} = x.${p("id")} and st.${s("archivedAt")} is null
    ), '[]'::jsonb))`;

  const idKey = { expr: `x.${p("id")}`, dir: "asc", type: "uuid" } as const;

  const rankKeys = [
    { expr: `x.${p("rank")} collate "C"`, dir: "asc", type: "text" },
    idKey,
  ] as const;

  const pipelinePage = {
    name: "page_pipelines",
    from: t("pipelines"),
    alias: "x",
    where: [
      `x.${p("tenant")} = page_pipelines.tenant`,
      `x.${p("archivedAt")} is null`,
      filterAny("subjectType", `x.${p("subjectType")}`),
      filterAny("key", `x.${p("key")}`),
      filterAny("scopeId", `x.${p("scope")}::text`),
      `(v_search is null or x.${p("name")} ilike v_search or x.${p("key")} ilike v_search)`,
    ],
    keys: rankKeys,
    sorts: {
      rank: rankKeys,
      name: [
        { expr: `lower(x.${p("name")})`, dir: "asc", type: "text" },
        idKey,
      ],
      key: [{ expr: `x.${p("key")}`, dir: "asc", type: "text" }, idKey],
    },
    facets: { subjectType: `x.${p("subjectType")}` },
    rowJson,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("PIPELINE_INVALID", message, "22023"),
  } as const;

  return `
-- The tenant's active pipelines as a keyset page, in board order (ADR 1077).
-- Runs with the caller's rights, so row level security decides what shows.
-- filters is { subjectType, key, scopeId (each a value or a list), search
-- (name, key), sort (rank, name, key), direction, facet, count, limit, after,
-- offset, paged, total, totalCap }.
create or replace function ${fn("page_pipelines")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_pipelines.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(pipelinePage)}
begin
  ${listBody(pipelinePage)}
end;
$$;
${userGrant(`${fn("page_pipelines")}(${idType}, jsonb)`)}

-- One active pipeline with its active stages, or a not-found error.
create or replace function ${fn("get_pipeline")}(pipeline uuid)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_row jsonb;
begin
  select ${rowJson} into v_row from ${t("pipelines")} x
  where x.${p("id")} = get_pipeline.pipeline and x.${p("archivedAt")} is null;
  if v_row is null then
    ${fail("PIPELINE_NOT_FOUND", "pipeline not found", "P0002")}
  end if;
  return v_row;
end;
$$;
${userGrant(`${fn("get_pipeline")}(uuid)`)}
`;
}
