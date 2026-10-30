import type { BlockSqlContext } from "../context.ts";

import { fail, pageSize, userGrant } from "../shared.ts";
import {
  definitionJson,
  observationJson,
  observationValue,
} from "./observations-functions.ts";
import { BUCKETS, sqlList } from "./observations-shared.ts";

/** The most observations one `list_observations` call returns. */
const MAX_ROWS = 1000;

/**
 * The reads. They run as the caller, so the tables' policies decide what comes
 * back: the observations of records the caller can read, in organizations where
 * they hold `observations.read`.
 */
export function observationReads(ctx: BlockSqlContext): string {
  const definitions = ctx.table("definitions");
  const observations = ctx.table("observations");
  const d = (column: string): string => ctx.col("definitions", column);
  const o = (column: string): string => ctx.col("observations", column);
  const fn = (name: string): string => ctx.fn(name);
  const idType = ctx.idType;

  const invalid = (message: string): string =>
    fail("OBSERVATION_INVALID", message, "22023");

  return `
-- An organization's definitions with the system ones it doesn't override,
-- by title.
create or replace function ${fn("list_observation_definitions")}(tenant ${idType}, include_archived boolean default false)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(${definitionJson(ctx, "x")} order by x.${d("title")}, x.${d("key")}), '[]'::jsonb)
  from ${definitions} x
  where (
      x.${d("tenant")} = list_observation_definitions.tenant
      or (x.${d("tenant")} is null and not exists (
        select 1 from ${definitions} y
        where y.${d("tenant")} = list_observation_definitions.tenant and y.${d("key")} = x.${d("key")}
      ))
    )
    and (coalesce(list_observation_definitions.include_archived, false) or x.${d("archivedAt")} is null)
$$;
${userGrant(`${fn("list_observation_definitions")}(${idType}, boolean)`)}

-- A record's observations, the latest first: the final ones, or with
-- include_all the amended and entered-in-error ones too.
create or replace function ${fn("list_observations")}(subject_type text, subject_id text, definition_key text default null, include_all boolean default false, max_rows integer default 100)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(r.item order by r.at desc, r.created desc), '[]'::jsonb)
  from (
    select ${observationJson(ctx, "x", "y")} as item, x.${o("observedAt")} as at, x.${o("createdAt")} as created
    from ${observations} x
    join ${definitions} y on y.${d("id")} = x.${o("definition")}
    where x.${o("subjectType")} = list_observations.subject_type
      and x.${o("subjectId")} = list_observations.subject_id
      and (list_observations.definition_key is null or y.${d("key")} = list_observations.definition_key)
      and (coalesce(list_observations.include_all, false) or x.${o("status")} = 'final')
    order by x.${o("observedAt")} desc, x.${o("createdAt")} desc
    limit ${pageSize("list_observations.max_rows", 100, MAX_ROWS)}
  ) r
$$;
${userGrant(`${fn("list_observations")}(text, text, text, boolean, integer)`)}

-- The final observations of one definition key for a record between since
-- and until (until excluded), oldest first. Without a bucket each point is
-- {id, observedAt, value, flag}; with hour, day, week or month (UTC) each
-- bucket has count, min, max and avg, per component for components.
create or replace function ${fn("observation_series")}(subject_type text, subject_id text, definition_key text, since timestamptz default null, until timestamptz default null, bucket text default null)
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if observation_series.bucket is not null and observation_series.bucket not in ${sqlList(BUCKETS)} then
    ${invalid(`bucket is one of ${BUCKETS.join(", ")}`)}
  end if;
  if observation_series.since is not null and observation_series.until is not null and observation_series.since > observation_series.until then
    ${invalid("since is before until")}
  end if;
  if observation_series.bucket is null then
    return (
      select coalesce(jsonb_agg(jsonb_build_object('id', x.${o("id")}, 'observedAt', x.${o("observedAt")}, 'value', ${observationValue(ctx, "x", "y")}, 'flag', x.${o("flag")}) order by x.${o("observedAt")}), '[]'::jsonb)
      from ${observations} x
      join ${definitions} y on y.${d("id")} = x.${o("definition")}
      where x.${o("subjectType")} = observation_series.subject_type
        and x.${o("subjectId")} = observation_series.subject_id
        and y.${d("key")} = observation_series.definition_key
        and x.${o("status")} = 'final'
        and (observation_series.since is null or x.${o("observedAt")} >= observation_series.since)
        and (observation_series.until is null or x.${o("observedAt")} < observation_series.until)
    );
  end if;
  return (
    with points as (
      select date_trunc(observation_series.bucket, x.${o("observedAt")}, 'UTC') as b, x.${o("valueNumber")} as n, x.${o("components")} as c
      from ${observations} x
      join ${definitions} y on y.${d("id")} = x.${o("definition")}
      where x.${o("subjectType")} = observation_series.subject_type
        and x.${o("subjectId")} = observation_series.subject_id
        and y.${d("key")} = observation_series.definition_key
        and x.${o("status")} = 'final'
        and (observation_series.since is null or x.${o("observedAt")} >= observation_series.since)
        and (observation_series.until is null or x.${o("observedAt")} < observation_series.until)
    ),
    parts as (
      select p.b, e.key, min(e.value::numeric) as lo, max(e.value::numeric) as hi, round(avg(e.value::numeric), 4) as mean
      from points p
      cross join lateral jsonb_each_text(coalesce(p.c, '{}'::jsonb)) e
      group by p.b, e.key
    )
    select coalesce(jsonb_agg(jsonb_build_object(
      'bucket', g.b,
      'count', g.total,
      'min', g.lo,
      'max', g.hi,
      'avg', g.mean,
      'components', coalesce((
        select jsonb_object_agg(q.key, jsonb_build_object('min', q.lo, 'max', q.hi, 'avg', q.mean))
        from parts q where q.b = g.b
      ), '{}'::jsonb)
    ) order by g.b), '[]'::jsonb)
    from (
      select p.b, count(*) as total, min(p.n) as lo, max(p.n) as hi, round(avg(p.n), 4) as mean
      from points p
      group by p.b
    ) g
  );
end;
$$;
${userGrant(`${fn("observation_series")}(text, text, text, timestamptz, timestamptz, text)`)}

-- A record's latest final observation per definition key, keyed by it.
create or replace function ${fn("latest_observations")}(subject_type text, subject_id text)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(r.key, r.item), '{}'::jsonb)
  from (
    select distinct on (y.${d("key")}) y.${d("key")} as key, ${observationJson(ctx, "x", "y")} as item
    from ${observations} x
    join ${definitions} y on y.${d("id")} = x.${o("definition")}
    where x.${o("subjectType")} = latest_observations.subject_type
      and x.${o("subjectId")} = latest_observations.subject_id
      and x.${o("status")} = 'final'
    order by y.${d("key")}, x.${o("observedAt")} desc, x.${o("createdAt")} desc
  ) r
$$;
${userGrant(`${fn("latest_observations")}(text, text)`)}
`;
}
