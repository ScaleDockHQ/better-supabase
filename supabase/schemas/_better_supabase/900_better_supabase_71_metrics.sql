-- better-supabase module: metrics (0.8.0)
-- @bs-module metrics@1 managed
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create table if not exists "better_supabase"."metric_points" (
  "tenant_id" uuid not null,
  "metric" text not null,
  "grain" text not null check ("grain" in ('hour', 'day', 'week', 'month')),
  "bucket_start" timestamptz not null,
  "dims" jsonb not null default '{}'::jsonb,
  "value" numeric not null,
  "count" bigint not null,
  "updated_at" timestamptz not null default now(),
  primary key ("tenant_id", "metric", "grain", "bucket_start", "dims")
);
alter table "better_supabase"."metric_points" enable row level security;
revoke all on "better_supabase"."metric_points" from anon, authenticated;
grant all on "better_supabase"."metric_points" to service_role;
create index if not exists metric_points_rollup_idx on "better_supabase"."metric_points" ("metric", "grain", "bucket_start");

-- Re-aggregates the window [since, until), default the last 3 days, so
-- rows that arrive late or change land in their buckets. Run it from cron or
-- a job; metricsSink runs it for the window of each event.
create or replace function "better_supabase"."metrics_rollup"(
  p_metric text default null,
  p_since timestamptz default null,
  p_until timestamptz default null
) returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_since timestamptz := coalesce(p_since, now() - interval '3 days');
  v_until timestamptz := coalesce(p_until, now());
  v_from timestamptz;
  v_to timestamptz;
  v_rows integer;
  v_total integer := 0;
begin
  if p_metric is not null and p_metric <> all (array['customers']::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;

  return v_total;
end;
$$;
revoke execute on function "better_supabase"."metrics_rollup"(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "better_supabase"."metrics_rollup"(text, timestamptz, timestamptz) to service_role;

-- One bucket per grain from [from, until), as { bucket, value, count } and
-- { groups } with group_by. Reads metric_points at a stored grain that
-- divides the requested one, otherwise the table.
create or replace function "better_supabase"."metric_series"(
  p_metric text,
  p_tenant uuid,
  p_from timestamptz,
  p_until timestamptz,
  p_grain text default 'day',
  p_dims jsonb default '{}'::jsonb,
  p_group_by text default null
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source text;
  v_start timestamptz;
  v_buckets integer;
begin
  if p_grain is null or p_grain <> all (array['hour', 'day', 'week', 'month']::text[]) then
    raise exception 'grain must be hour, day, week or month' using errcode = '22023', hint = 'METRIC_GRAIN_INVALID';
  end if;
  if p_from is null or p_until is null or p_until <= p_from then
    raise exception 'the range needs a start before its end' using errcode = '22023', hint = 'METRIC_RANGE_INVALID';
  end if;
  case p_metric
    when 'customers' then
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'metrics.read'), false)) then
        raise exception 'you cannot read this metric in this organization' using errcode = '42501', hint = 'METRIC_FORBIDDEN';
      end if;
      if exists (
        select 1 from jsonb_object_keys(coalesce(p_dims, '{}'::jsonb)) k
        where k <> all (array['status']::text[])
      ) then
        raise exception 'a filter names a column that is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      if p_group_by is not null and p_group_by <> all (array['status']::text[]) then
        raise exception 'group_by is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      v_source := null;
      v_start := date_trunc(p_grain, p_from, 'UTC');
      select count(*) into v_buckets
        from generate_series(v_start at time zone 'UTC', (p_until at time zone 'UTC') - interval '1 microsecond', ('1 ' || p_grain)::interval);
      if v_buckets > 1000 then
        raise exception 'a series returns at most 1000 buckets; pick a coarser grain' using errcode = '22023', hint = 'METRIC_RANGE_TOO_LARGE';
      end if;
      return (
        with source as (
      select s.at, s.dims, s.value, s.count
        from (select t."organization_id" as tenant, t."created_at" as at, jsonb_build_object('status', t."status") as dims, 1::numeric as value, 1::bigint as count
        from "public"."customers" t
        where t."archived_at" is null) s
        where v_source is null
          and s.tenant = p_tenant
          and s.at >= v_start
          and s.at < p_until
          and s.dims @> coalesce(p_dims, '{}'::jsonb)
    ),
        buckets as (
          select b at time zone 'UTC' as bucket
            from generate_series(v_start at time zone 'UTC', (p_until at time zone 'UTC') - interval '1 microsecond', ('1 ' || p_grain)::interval) b
        ),
        grouped as (
          select date_trunc(p_grain, s.at, 'UTC') as bucket,
                 case when p_group_by is null then null else s.dims ->> p_group_by end as grp,
                 sum(s.value) as value,
                 sum(s.count) as count
            from source s
            group by 1, 2
        ),
        per_bucket as (
          select g.bucket, sum(g.value) as value, sum(g.count) as count,
                 jsonb_object_agg(coalesce(g.grp, ''), coalesce(g.value, 0)) as groups
            from grouped g
            group by g.bucket
        )
        select coalesce(jsonb_agg(
          jsonb_build_object('bucket', b.bucket, 'value', coalesce(p.value, 0), 'count', coalesce(p.count, 0))
            || case when p_group_by is null then '{}'::jsonb else jsonb_build_object('groups', coalesce(p.groups, '{}'::jsonb)) end
          order by b.bucket), '[]'::jsonb)
          from buckets b
          left join per_bucket p on p.bucket = b.bucket
      );
    else
      raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) from public, anon;
grant execute on function "better_supabase"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) to authenticated, service_role;

-- The total over [from, until), as { value, count }, from the finest stored
-- grain (whole buckets) or the table.
create or replace function "better_supabase"."metric_value"(
  p_metric text,
  p_tenant uuid,
  p_from timestamptz,
  p_until timestamptz,
  p_dims jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  v_source text;
begin
  if p_from is null or p_until is null or p_until <= p_from then
    raise exception 'the range needs a start before its end' using errcode = '22023', hint = 'METRIC_RANGE_INVALID';
  end if;
  case p_metric
    when 'customers' then
      if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', p_tenant, 'metrics.read'), false)) then
        raise exception 'you cannot read this metric in this organization' using errcode = '42501', hint = 'METRIC_FORBIDDEN';
      end if;
      if exists (
        select 1 from jsonb_object_keys(coalesce(p_dims, '{}'::jsonb)) k
        where k <> all (array['status']::text[])
      ) then
        raise exception 'a filter names a column that is not a dimension of this metric' using errcode = '22023', hint = 'METRIC_DIMENSION_UNKNOWN';
      end if;
      v_source := null;
      return (
        with source as (
      select s.at, s.dims, s.value, s.count
        from (select t."organization_id" as tenant, t."created_at" as at, jsonb_build_object('status', t."status") as dims, 1::numeric as value, 1::bigint as count
        from "public"."customers" t
        where t."archived_at" is null) s
        where v_source is null
          and s.tenant = p_tenant
          and s.at >= p_from
          and s.at < p_until
          and s.dims @> coalesce(p_dims, '{}'::jsonb)
    ),
        total as (select sum(s.value) as value, sum(s.count) as count from source s)
        select jsonb_build_object('value', coalesce(t.value, 0), 'count', coalesce(t.count, 0))
          from total t
      );
    else
      raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end case;
end;
$$;
revoke execute on function "better_supabase"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) from public, anon;
grant execute on function "better_supabase"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) to authenticated, service_role;

-- The declared metrics, for pickers and chart labels.
create or replace function "better_supabase"."metric_definitions"()
returns jsonb
language sql
immutable
set search_path = ''
as $$ select '[{"key":"customers","label":"Customers","unit":null,"measure":"count","dimensions":["status"],"grains":[],"tz":"UTC"}]'::jsonb $$;
revoke execute on function "better_supabase"."metric_definitions"() from public, anon;
grant execute on function "better_supabase"."metric_definitions"() to authenticated, service_role;

-- blocks.metrics.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."metrics_rollup"(p_metric text default null, p_since timestamptz default null, p_until timestamptz default null)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."metrics_rollup"($1, $2, $3) $$;
revoke execute on function "api"."metrics_rollup"(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "api"."metrics_rollup"(text, timestamptz, timestamptz) to service_role;

create or replace function "api"."metric_series"(p_metric text, p_tenant uuid, p_from timestamptz, p_until timestamptz, p_grain text default 'day', p_dims jsonb default '{}'::jsonb, p_group_by text default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."metric_series"($1, $2, $3, $4, $5, $6, $7) $$;
revoke execute on function "api"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) from public, anon;
grant execute on function "api"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) to authenticated, service_role;

create or replace function "api"."metric_value"(p_metric text, p_tenant uuid, p_from timestamptz, p_until timestamptz, p_dims jsonb default '{}'::jsonb)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."metric_value"($1, $2, $3, $4, $5) $$;
revoke execute on function "api"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) from public, anon;
grant execute on function "api"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) to authenticated, service_role;

create or replace function "api"."metric_definitions"()
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."metric_definitions"() $$;
revoke execute on function "api"."metric_definitions"() from public, anon;
grant execute on function "api"."metric_definitions"() to authenticated, service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.modules (
  name text primary key,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.modules enable row level security;
revoke all on better_supabase.modules from anon, authenticated;
grant select on better_supabase.modules to service_role;
