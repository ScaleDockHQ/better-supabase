import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterFlag,
  filterSet,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, userGrant } from "../shared.ts";
import { definitionJson, observationJson } from "./observations-functions.ts";

/**
 * The keyset page functions of the observations block (ADR 1077). They run as
 * the caller like the other reads, so the tables' policies decide which rows
 * come back.
 */
export function observationPages(ctx: BlockSqlContext): string {
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const oKey = { expr: `x.${o("id")}`, dir: "desc", type: "uuid" } as const;

  const latest = [
    { expr: `x.${o("observedAt")}`, dir: "desc", type: "timestamptz" },
    { expr: `x.${o("createdAt")}`, dir: "desc", type: "timestamptz" },
    oKey,
  ] as const;

  const definitionOf = `(select y.${d("key")} from ${definitions} y where y.${d("id")} = x.${o("definition")})`;

  const observationPage = {
    name: "page_observations",
    from: observations,
    alias: "x",
    where: [
      filterAny("subjectType", `x.${o("subjectType")}`),
      filterAny("subjectId", `x.${o("subjectId")}`),
      filterAny("definitionKey", definitionOf),
      `(case when ${filterSet("status")} then ${filterAny("status", `x.${o("status")}::text`)} else x.${o("status")} = 'final' end)`,
    ],
    keys: latest,
    sorts: {
      observedAt: latest,
      createdAt: [
        { expr: `x.${o("createdAt")}`, dir: "desc", type: "timestamptz" },
        oKey,
      ],
    },
    facets: { status: `x.${o("status")}::text`, definitionKey: definitionOf },
    rowJson: `(select ${observationJson(ctx, "x", "y")} from ${definitions} y where y.${d("id")} = x.${o("definition")})`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("OBSERVATION_INVALID", message, "22023"),
  } as const;

  const dKey = { expr: `x.${d("id")}`, dir: "asc", type: "uuid" } as const;

  const byTitle = [
    { expr: `lower(x.${d("title")})`, dir: "asc", type: "text" },
    { expr: `x.${d("key")}`, dir: "asc", type: "text" },
    dKey,
  ] as const;

  const scope = `case when x.${d("tenant")} is null then 'system' else 'organization' end`;

  const definitionPage = {
    name: "page_observation_definitions",
    from: definitions,
    alias: "x",
    where: [
      `(x.${d("tenant")} = page_observation_definitions.tenant or (x.${d("tenant")} is null and not exists (select 1 from ${definitions} y where y.${d("tenant")} = page_observation_definitions.tenant and y.${d("key")} = x.${d("key")})))`,
      `(${filterFlag("archived")} or x.${d("archivedAt")} is null)`,
      filterAny("valueType", `x.${d("valueType")}::text`),
      filterAny("scope", scope),
      `(v_search is null or x.${d("title")} ilike v_search or x.${d("key")} ilike v_search)`,
    ],
    keys: byTitle,
    sorts: {
      title: byTitle,
      key: [{ expr: `x.${d("key")}`, dir: "asc", type: "text" }, dKey],
    },
    facets: { valueType: `x.${d("valueType")}::text`, scope },
    rowJson: definitionJson(ctx, "x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid: (message: string) => fail("OBSERVATION_INVALID", message, "22023"),
  } as const;

  return `
-- A record's observations as a keyset page, the latest first (ADR 1077).
-- filters is { subjectType, subjectId, definitionKey, status (each a value or
-- a list; without status only final observations), sort (observedAt,
-- createdAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }.
create or replace function ${fn("page_observations")}(filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_observations.filters, '{}'::jsonb);
  v_search text := null;
  ${listDeclare(observationPage)}
begin
  ${listBody(observationPage)}
end;
$$;
${userGrant(`${fn("page_observations")}(jsonb)`)}

-- One observation the caller reads, or null.
create or replace function ${fn("get_observation")}(observation_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${observationJson(ctx, "x", "y")}
  from ${observations} x
  join ${definitions} y on y.${d("id")} = x.${o("definition")}
  where x.${o("id")} = get_observation.observation_id
$$;
${userGrant(`${fn("get_observation")}(uuid)`)}

-- An organization's definitions with the system ones it does not override, as
-- a keyset page by title.
create or replace function ${fn("page_observation_definitions")}(tenant ${idType}, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_observation_definitions.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(definitionPage)}
begin
  ${listBody(definitionPage)}
end;
$$;
${userGrant(`${fn("page_observation_definitions")}(${idType}, jsonb)`)}

-- One definition the caller reads, or null.
create or replace function ${fn("get_observation_definition")}(definition_id uuid)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select ${definitionJson(ctx, "x")} from ${definitions} x where x.${d("id")} = get_observation_definition.definition_id
$$;
${userGrant(`${fn("get_observation_definition")}(uuid)`)}
`;
}
