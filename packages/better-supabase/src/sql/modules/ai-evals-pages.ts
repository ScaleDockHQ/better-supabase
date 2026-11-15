import type { BlockSqlContext } from "../context.ts";

import {
  filterAny,
  filterHasInvalid,
  listBody,
  listDeclare,
  searchPattern,
} from "../list-template.ts";
import { fail, serviceGrant } from "../shared.ts";

/** What the ai-evals module's `build` hands the page functions. */
export interface EvalPageDeps {
  readonly datasetJson: (row: string) => string;
  readonly runJson: (row: string) => string;
}

/**
 * `page_eval_datasets` and `page_eval_runs`: the keyset pages of the block list
 * contract (ADR 1077). Only the service role calls them, as it does
 * `list_eval_datasets`.
 */
export function evalPagesSql(ctx: BlockSqlContext, deps: EvalPageDeps): string {
  const id = ctx.idType;
  const fn = (name: string): string => ctx.fn(name);
  const d = (column: string): string => ctx.col("datasets", column);
  const r = (column: string): string => ctx.col("runs", column);
  const i = (column: string): string => ctx.col("items", column);
  const datasets = ctx.table("datasets");
  const runs = ctx.table("runs");
  const items = ctx.table("items");

  const invalid = (message: string): string =>
    fail("EVAL_INVALID", message, "22023");

  const datasetIdKey = {
    expr: `x.${d("id")}`,
    dir: "asc",
    type: "uuid",
  } as const;

  const runIdKey = { expr: `x.${r("id")}`, dir: "desc", type: "uuid" } as const;

  const lastRun = `(select max(y.${r("createdAt")}) from ${runs} y where y.${r("dataset")} = x.${d("id")})`;

  const byName = [
    { expr: `x.${d("name")}`, dir: "asc", type: "text" },
    datasetIdKey,
  ] as const;

  const datasetPage = {
    name: "page_eval_datasets",
    from: datasets,
    alias: "x",
    where: [
      `coalesce(x.${d("tenant")}::text, '') = coalesce(page_eval_datasets.tenant::text, '')`,
      filterAny("id", `x.${d("id")}`, "uuid"),
      `(v_search is null or x.${d("name")} ilike v_search)`,
    ],
    keys: byName,
    sorts: {
      name: byName,
      createdAt: [
        { expr: `x.${d("createdAt")}`, dir: "desc", type: "timestamptz" },
        datasetIdKey,
      ],
      lastRunAt: [
        {
          expr: `coalesce(${lastRun}, 'epoch'::timestamptz)`,
          dir: "desc",
          type: "timestamptz",
        },
        datasetIdKey,
      ],
    },
    facets: {},
    rowJson: `${deps.datasetJson("x")} || jsonb_build_object(
      'item_count', (select count(*) from ${items} i where i.${i("dataset")} = x.${d("id")}),
      'run_count', (select count(*) from ${runs} y where y.${r("dataset")} = x.${d("id")}),
      'last_run_at', ${lastRun}
    )`,
    defaultLimit: 50,
    maxLimit: 200,
    invalid,
  } as const;

  const newest = [
    { expr: `x.${r("createdAt")}`, dir: "desc", type: "timestamptz" },
    runIdKey,
  ] as const;

  const runPage = {
    name: "page_eval_runs",
    from: runs,
    alias: "x",
    where: [
      `coalesce(x.${r("tenant")}::text, '') = coalesce(page_eval_runs.tenant::text, '')`,
      filterAny("datasetId", `x.${r("dataset")}`, "uuid"),
      filterAny("status", `x.${r("status")}`),
      filterAny("model", `x.${r("model")}`),
      filterAny("promptName", `x.${r("promptName")}`),
      `(v_search is null or x.${r("promptName")} ilike v_search or x.${r("model")} ilike v_search)`,
    ],
    keys: newest,
    sorts: {
      createdAt: newest,
      finishedAt: [
        {
          expr: `coalesce(x.${r("finishedAt")}, 'epoch'::timestamptz)`,
          dir: "desc",
          type: "timestamptz",
        },
        runIdKey,
      ],
    },
    facets: {
      status: `x.${r("status")}`,
      model: `x.${r("model")}`,
      promptName: `x.${r("promptName")}`,
    },
    rowJson: deps.runJson("x"),
    defaultLimit: 50,
    maxLimit: 200,
    invalid,
  } as const;

  return `-- A tenant's datasets (the system's when tenant is null) as a keyset page (ADR
-- 1077), by name, each with its item count, run count and latest run. filters
-- is { id (a uuid or a list), search (name), sort (name, createdAt,
-- lastRunAt), direction, facet, count, limit, after, offset, paged, total,
-- totalCap }. It runs as invoker: only the service role calls it.
create or replace function ${fn("page_eval_datasets")}(tenant ${id} default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_eval_datasets.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(datasetPage)}
begin
  if ${filterHasInvalid("id")} then
    ${invalid("id is a uuid")}
  end if;
  ${listBody(datasetPage)}
end;
$$;
${serviceGrant(`${fn("page_eval_datasets")}(${id}, jsonb)`)}

-- A tenant's runs (the system's when tenant is null) as a keyset page (ADR
-- 1077), newest first. filters is { datasetId (a uuid or a list), status,
-- model, promptName (a value or a list), search (prompt name, model), sort
-- (createdAt, finishedAt), direction, facet, count, limit, after, offset,
-- paged, total, totalCap }.
create or replace function ${fn("page_eval_runs")}(tenant ${id} default null, filters jsonb default '{}')
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(page_eval_runs.filters, '{}'::jsonb);
  v_search text := ${searchPattern()};
  ${listDeclare(runPage)}
begin
  if ${filterHasInvalid("datasetId")} then
    ${invalid("datasetId is a uuid")}
  end if;
  ${listBody(runPage)}
end;
$$;
${serviceGrant(`${fn("page_eval_runs")}(${id}, jsonb)`)}`;
}
