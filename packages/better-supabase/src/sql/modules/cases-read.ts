import type { BlockSqlContext } from "../context.ts";
import type { CasesSql } from "./cases-sql.ts";

import { pageSize, userGrant } from "../shared.ts";
import { CASE_STATS_GROUPS, casesSql } from "./cases-sql.ts";

function actionsJson(q: CasesSql, row: string): string {
  const { a, c, actions } = q;
  const tasks = q.tasks;

  if (tasks === undefined) {
    return `coalesce((
      select jsonb_agg(jsonb_build_object('id', x.${a("id")}, 'taskId', x.${a("task")}, 'type', x.${a("type")}, 'required', x.${a("required")}, 'createdAt', x.${a("createdAt")}) order by x.${a("createdAt")})
      from ${actions} x where x.${a("case")} = ${row}.${c("id")}
    ), '[]'::jsonb)`;
  }

  const i = (column: string): string => `i.${tasks.col("items", column)}`;
  const s = (column: string): string => `s.${tasks.col("assignees", column)}`;

  return `coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', x.${a("id")}, 'taskId', x.${a("task")}, 'type', x.${a("type")}, 'required', x.${a("required")}, 'createdAt', x.${a("createdAt")},
        'title', ${i("title")}, 'state', ${i("state")}, 'dueAt', ${i("dueAt")},
        'done', ${tasks.is("items", "state", i("state"), ["completed", "canceled"])},
        'assignees', coalesce((select jsonb_agg(${s("user")}) from ${tasks.table("assignees")} s where ${s("item")} = x.${a("task")}), '[]'::jsonb)
      ) order by x.${a("createdAt")})
      from ${actions} x
      left join ${tasks.table("items")} i on ${i("id")} = x.${a("task")}
      where x.${a("case")} = ${row}.${c("id")}
    ), '[]'::jsonb)`;
}

function relationCounts(q: CasesSql, row: string): string {
  const relations = q.relations;

  if (relations === undefined) {
    return "'{}'::jsonb";
  }

  const r = (column: string): string =>
    `r.${relations.col("relations", column)}`;

  return `coalesce((
      select jsonb_object_agg(k.kind, k.count) from (
        select ${r("kind")} as kind, count(*) as count
        from ${relations.table("relations")} r
        where (${r("sourceType")} = ${q.subject} and ${r("sourceId")} = ${row}.${q.c("id")}::text)
          or (${r("targetType")} = ${q.subject} and ${r("targetId")} = ${row}.${q.c("id")}::text)
        group by ${r("kind")}
      ) k
    ), '{}'::jsonb)`;
}

function reads(ctx: BlockSqlContext, q: CasesSql): string {
  const { fn, k, c, cases, kinds, caseJson, kindJson } = q;
  const idType = ctx.idType;
  const p = q.pipelines;

  const search = [
    `x.${c("title")} ilike v_search`,
    `x.${c("number")} ilike v_search`,
    ...(q.has("cases", "description")
      ? [`x.${c("description")} ilike v_search`]
      : []),
    `x.${c("rootCause")} ilike v_search`,
  ].join(" or ");

  const groups = CASE_STATS_GROUPS.map((group) => `'${group}'`).join(", ");

  return `
-- A case with its kind, its actions (with the work item's title, state and
-- assignees), what blocks closing it and how many links of each relation kind it has.
create or replace function ${fn("get_case")}(case_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_row ${cases};
  v_kind ${kinds};
begin
  select * into v_row from ${cases} x where x.${c("id")} = get_case.case_id;
  if not found then
    ${q.missing}
  end if;
  if not ${q.allowed(`v_row.${c("tenant")}`, q.read)} then
    ${q.forbidden("not allowed to read cases")}
  end if;
  select * into v_kind from ${kinds} x where x.${k("id")} = v_row.${c("kind")};
  return ${caseJson("v_row")} || jsonb_build_object(
    'kind', ${kindJson("v_kind")},
    'stage', (select jsonb_build_object('id', s.${p.col("stages", "id")}, 'key', s.${p.col("stages", "key")}, 'name', s.${p.col("stages", "name")}, 'outcome', s.${p.col("stages", "outcome")})
      from ${p.table("stages")} s where s.${p.col("stages", "id")} = v_row.${c("stage")}),
    'actions', ${actionsJson(q, "v_row")},
    'blockers', to_jsonb(${fn("case_blockers_of")}(v_row)),
    'relations', ${relationCounts(q, "v_row")}
  );
end;
$$;
${userGrant(`${fn("get_case")}(uuid)`)}

-- The organization's cases, newest first, a page at a time. filters: kind
-- (a key), status, severity, source, owner, stage, overdue (dueOn passed),
-- search, limit (up to 200) and cursor (the nextCursor of the last page).
create or replace function ${fn("list_cases")}(tenant ${idType}, filters jsonb default '{}'::jsonb)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
declare
  v_filters jsonb := coalesce(list_cases.filters, '{}'::jsonb);
  v_search text := case when nullif(trim(v_filters ->> 'search'), '') is null then null
    else '%' || replace(replace(replace(trim(v_filters ->> 'search'), '\\', '\\\\'), '%', '\\%'), '_', '\\_') || '%' end;
  v_limit integer := ${pageSize("(v_filters ->> 'limit')::integer", 50, 200)};
  v_after_at timestamptz;
  v_after_id uuid;
  v_items jsonb;
  v_count integer;
begin
  if not ${q.allowed("list_cases.tenant", q.read)} then
    ${q.forbidden("not allowed to read cases")}
  end if;
  if jsonb_typeof(v_filters) <> 'object' then
    ${q.invalid("filters must be an object")}
  end if;
  if nullif(v_filters ->> 'cursor', '') is not null then
    begin
      v_after_at := split_part(v_filters ->> 'cursor', '|', 1)::timestamptz;
      v_after_id := split_part(v_filters ->> 'cursor', '|', 2)::uuid;
    exception when others then
      ${q.invalid("cursor is not a nextCursor of list_cases")}
    end;
  end if;
  select coalesce(jsonb_agg(${caseJson("x")} order by x.${c("createdAt")} desc, x.${c("id")} desc), '[]'::jsonb), count(*)
  into v_items, v_count
  from (
    select * from ${cases} x
    where x.${c("tenant")} = list_cases.tenant
      and x.${c("archivedAt")} is null
      and (not v_filters ? 'kind' or x.${c("kind")} = (select y.${k("id")} from ${kinds} y where y.${k("tenant")} = list_cases.tenant and y.${k("key")} = v_filters ->> 'kind'))
      and (not v_filters ? 'status' or x.${c("status")} = v_filters ->> 'status')
      and (not v_filters ? 'severity' or x.${c("severity")} = v_filters ->> 'severity')
      and (not v_filters ? 'source' or x.${c("source")} = v_filters ->> 'source')
      and (not v_filters ? 'owner' or x.${c("owner")} = (v_filters ->> 'owner')::uuid)
      and (not v_filters ? 'stage' or x.${c("stage")} = (v_filters ->> 'stage')::uuid)
      and (coalesce((v_filters ->> 'overdue')::boolean, false) is false or (x.${c("status")} = 'open' and x.${c("dueOn")} < current_date))
      and (v_search is null or ${search})
      and (v_after_at is null or (x.${c("createdAt")}, x.${c("id")}) < (v_after_at, v_after_id))
    order by x.${c("createdAt")} desc, x.${c("id")} desc
    limit v_limit
  ) x;
  return jsonb_build_object(
    'items', v_items,
    'nextCursor', case when v_count = v_limit
      then (v_items -> -1 ->> 'createdAt') || '|' || (v_items -> -1 ->> 'id')
      else null end);
end;
$$;
${userGrant(`${fn("list_cases")}(${idType}, jsonb)`)}

-- How many cases there are per severity, source, stage, kind or root cause,
-- most first (a Pareto), optionally of one kind and opened between since and
-- until. Returns [{ key, count }]; a case without a value counts under null.
create or replace function ${fn("case_stats")}(tenant ${idType}, kind text default null, since date default null, until date default null, group_by text default 'severity')
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
#variable_conflict use_variable
begin
  if not ${q.allowed("case_stats.tenant", q.read)} then
    ${q.forbidden("not allowed to read cases")}
  end if;
  if coalesce(case_stats.group_by, '') not in (${groups}) then
    ${q.invalid("group_by is severity, source, stage, kind or root_cause")}
  end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object('key', g.key, 'count', g.count) order by g.count desc, g.key nulls last)
    from (
      select case case_stats.group_by
          when 'severity' then x.${c("severity")}
          when 'source' then x.${c("source")}
          when 'stage' then (select s.${p.col("stages", "key")} from ${p.table("stages")} s where s.${p.col("stages", "id")} = x.${c("stage")})
          when 'kind' then y.${k("key")}
          else nullif(lower(trim(x.${c("rootCause")})), '')
        end as key,
        count(*) as count
      from ${cases} x
      join ${kinds} y on y.${k("id")} = x.${c("kind")}
      where x.${c("tenant")} = case_stats.tenant
        and x.${c("archivedAt")} is null
        and (case_stats.kind is null or y.${k("key")} = case_stats.kind)
        and (case_stats.since is null or x.${c("createdAt")} >= case_stats.since)
        and (case_stats.until is null or x.${c("createdAt")} < case_stats.until + 1)
      group by 1
    ) g
  ), '[]'::jsonb);
end;
$$;
${userGrant(`${fn("case_stats")}(${idType}, text, date, date, text)`)}
`;
}

export function caseReadFunctions(ctx: BlockSqlContext): string {
  return reads(ctx, casesSql(ctx));
}
