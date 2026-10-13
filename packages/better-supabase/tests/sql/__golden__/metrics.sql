-- ==== alone: schema supabase/schemas/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module metrics@1 managed
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
  if p_metric is not null and p_metric <> all (array[]::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
as $$ select '[]'::jsonb $$;
revoke execute on function "better_supabase"."metric_definitions"() from public, anon;
grant execute on function "better_supabase"."metric_definitions"() to authenticated, service_role;

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

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module-data metrics
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module metrics@1 managed
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
  if p_metric is not null and p_metric <> all (array[]::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
as $$ select '[]'::jsonb $$;
revoke execute on function "better_supabase"."metric_definitions"() from public, anon;
grant execute on function "better_supabase"."metric_definitions"() to authenticated, service_role;

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

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module-data metrics
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module metrics@1 managed
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
create table if not exists "app_private"."metric_points" (
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
alter table "app_private"."metric_points" enable row level security;
revoke all on "app_private"."metric_points" from anon, authenticated;
grant all on "app_private"."metric_points" to service_role;
create index if not exists metric_points_rollup_idx on "app_private"."metric_points" ("metric", "grain", "bucket_start");

-- Re-aggregates the window [since, until), default the last 3 days, so
-- rows that arrive late or change land in their buckets. Run it from cron or
-- a job; metricsSink runs it for the window of each event.
create or replace function "app_private"."metrics_rollup"(
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
  if p_metric is not null and p_metric <> all (array[]::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

  return v_total;
end;
$$;
revoke execute on function "app_private"."metrics_rollup"(text, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function "app_private"."metrics_rollup"(text, timestamptz, timestamptz) to service_role;

-- One bucket per grain from [from, until), as { bucket, value, count } and
-- { groups } with group_by. Reads metric_points at a stored grain that
-- divides the requested one, otherwise the table.
create or replace function "app_private"."metric_series"(
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) from public, anon;
grant execute on function "app_private"."metric_series"(text, uuid, timestamptz, timestamptz, text, jsonb, text) to authenticated, service_role;

-- The total over [from, until), as { value, count }, from the finest stored
-- grain (whole buckets) or the table.
create or replace function "app_private"."metric_value"(
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
end;
$$;
revoke execute on function "app_private"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) from public, anon;
grant execute on function "app_private"."metric_value"(text, uuid, timestamptz, timestamptz, jsonb) to authenticated, service_role;

-- The declared metrics, for pickers and chart labels.
create or replace function "app_private"."metric_definitions"()
returns jsonb
language sql
immutable
set search_path = ''
as $$ select '[]'::jsonb $$;
revoke execute on function "app_private"."metric_definitions"() from public, anon;
grant execute on function "app_private"."metric_definitions"() to authenticated, service_role;

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

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module-data metrics
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module metrics@1 managed
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

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
  if p_metric is not null and p_metric <> all (array[]::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
as $$ select '[]'::jsonb $$;
revoke execute on function "better_supabase"."metric_definitions"() from public, anon;
grant execute on function "better_supabase"."metric_definitions"() to authenticated, service_role;

-- sql.modules.metrics.api: entry points for the Data API.
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module-data metrics
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('metrics', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== adopt: schema supabase/schemas/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module metrics@1 adopt
-- Metrics declared with defineMetric over a table (count, sum or avg per time bucket and dimension), rolled up into metric_points or read from the table, with metric_series and metric_value checked against a permission in the tenant.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

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
  if p_metric is not null and p_metric <> all (array[]::text[]) then
    raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
  end if;
  if v_until <= v_since then
    return 0;
  end if;
  perform pg_advisory_xact_lock(hashtext('better_supabase.metrics_rollup'));

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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
  raise exception 'no metric has this key' using errcode = '22023', hint = 'METRIC_UNKNOWN';
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
as $$ select '[]'::jsonb $$;
revoke execute on function "better_supabase"."metric_definitions"() from public, anon;
grant execute on function "better_supabase"."metric_definitions"() to authenticated, service_role;

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

-- ==== adopt: data supabase/better-supabase-data/900_better_supabase_68_metrics.sql
-- better-supabase module: metrics
-- @bs-module-data metrics
-- Rows and settings a schema diff doesn't capture. Run `better-supabase sql data`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.modules (name, version, mode)
values ('metrics', 1, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
