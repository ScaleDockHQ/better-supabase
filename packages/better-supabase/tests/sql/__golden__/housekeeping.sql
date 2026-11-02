-- ==== alone: schema supabase/schemas/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block housekeeping@1 managed
-- @bsb-hash sha256:f6d9b6cc4b41cc0ca0405637b7e7a21268729cc2a5e795a8c3dd5e4381e91a21
-- One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One row per job the dispatcher ran: when, with what result, and how often.
create table if not exists "better_supabase"."maintenance_state" (
  "job" text primary key,
  "last_run_at" timestamptz,
  "last_status" text check ("last_status" in ('ok', 'error')),
  "last_result" jsonb,
  "last_error" text,
  "runs" bigint not null default 0
);
alter table "better_supabase"."maintenance_state" enable row level security;
revoke all on "better_supabase"."maintenance_state" from public, anon, authenticated;
grant all on "better_supabase"."maintenance_state" to service_role;

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' `housekeeping` contributions.
create or replace view "better_supabase"."maintenance_jobs" with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s."last_run_at" as last_run_at, s."last_status" as last_status, s."last_error" as last_error,
  coalesce(s."runs", 0) as runs,
  (s."last_run_at" is null or s."last_run_at" + j.every_interval <= now()) as due
from (select null::text, null::text, null::interval where false) j (job, fn, every_interval)
left join "better_supabase"."maintenance_state" s on s."job" = j.job;
revoke all on "better_supabase"."maintenance_jobs" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_jobs" to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function "better_supabase"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "better_supabase"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function "better_supabase"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "better_supabase"."maintenance"()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function "better_supabase"."maintenance_scheduler"()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

revoke execute on function better_supabase.maintenance(text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.maintenance(text, boolean) to service_role;
revoke execute on function better_supabase.maintenance_schedule(text) from public, anon, authenticated;
grant execute on function better_supabase.maintenance_schedule(text) to service_role;
revoke execute on function better_supabase.maintenance_scheduler() from public, anon, authenticated;
grant execute on function better_supabase.maintenance_scheduler() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block-data housekeeping
-- @bsb-hash sha256:6a87df78cad56be6b8e3240ea5ddeafcaac1a50276e719091119cd1fef511897
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block housekeeping@1 managed
-- @bsb-hash sha256:ba7d5f104418aa52091e939d79966f166f16d42dc2dfb6d235153081052eb001
-- One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One row per job the dispatcher ran: when, with what result, and how often.
create table if not exists "better_supabase"."maintenance_state" (
  "job" text primary key,
  "last_run_at" timestamptz,
  "last_status" text check ("last_status" in ('ok', 'error')),
  "last_result" jsonb,
  "last_error" text,
  "runs" bigint not null default 0
);
alter table "better_supabase"."maintenance_state" enable row level security;
revoke all on "better_supabase"."maintenance_state" from public, anon, authenticated;
grant all on "better_supabase"."maintenance_state" to service_role;

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' `housekeeping` contributions.
create or replace view "better_supabase"."maintenance_jobs" with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s."last_run_at" as last_run_at, s."last_status" as last_status, s."last_error" as last_error,
  coalesce(s."runs", 0) as runs,
  (s."last_run_at" is null or s."last_run_at" + j.every_interval <= now()) as due
from (values
    ('expire_approvals', '"better_supabase"."expire_approvals"', interval '15 minutes'),
    ('purge_chat_state', '"better_supabase"."purge_chat_state"', interval '15 minutes'),
    ('purge_expired_trash', '"better_supabase"."purge_expired_trash"', interval '1 day'),
    ('purge_idempotency_keys', 'better_supabase.purge_idempotency_keys', interval '1 hour'),
    ('purge_rate_limits', 'better_supabase.purge_rate_limits', interval '15 minutes'),
    ('purge_webhooks', 'better_supabase.purge_webhooks', interval '1 day')
  ) j (job, fn, every_interval)
left join "better_supabase"."maintenance_state" s on s."job" = j.job;
revoke all on "better_supabase"."maintenance_jobs" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_jobs" to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function "better_supabase"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "better_supabase"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function "better_supabase"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "better_supabase"."maintenance"()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function "better_supabase"."maintenance_scheduler"()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

revoke execute on function better_supabase.maintenance(text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.maintenance(text, boolean) to service_role;
revoke execute on function better_supabase.maintenance_schedule(text) from public, anon, authenticated;
grant execute on function better_supabase.maintenance_schedule(text) to service_role;
revoke execute on function better_supabase.maintenance_scheduler() from public, anon, authenticated;
grant execute on function better_supabase.maintenance_scheduler() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block-data housekeeping
-- @bsb-hash sha256:6a87df78cad56be6b8e3240ea5ddeafcaac1a50276e719091119cd1fef511897
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block housekeeping@1 managed
-- @bsb-hash sha256:8dc1e0b572d1a78d2413d20d8e7d2b12f010dd7c211a05860261e3e347748f62
-- One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;

-- One row per job the dispatcher ran: when, with what result, and how often.
create table if not exists "app_private"."maintenance_state" (
  "job" text primary key,
  "last_run_at" timestamptz,
  "last_status" text check ("last_status" in ('ok', 'error')),
  "last_result" jsonb,
  "last_error" text,
  "runs" bigint not null default 0
);
alter table "app_private"."maintenance_state" enable row level security;
revoke all on "app_private"."maintenance_state" from public, anon, authenticated;
grant all on "app_private"."maintenance_state" to service_role;

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' `housekeeping` contributions.
create or replace view "app_private"."maintenance_jobs" with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s."last_run_at" as last_run_at, s."last_status" as last_status, s."last_error" as last_error,
  coalesce(s."runs", 0) as runs,
  (s."last_run_at" is null or s."last_run_at" + j.every_interval <= now()) as due
from (select null::text, null::text, null::interval where false) j (job, fn, every_interval)
left join "app_private"."maintenance_state" s on s."job" = j.job;
revoke all on "app_private"."maintenance_jobs" from public, anon, authenticated;
grant select on "app_private"."maintenance_jobs" to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function "app_private"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "app_private"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "app_private"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "app_private"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "app_private"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "app_private"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function "app_private"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "app_private"."maintenance"()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function "app_private"."maintenance_scheduler"()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

revoke execute on function better_supabase.maintenance(text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.maintenance(text, boolean) to service_role;
revoke execute on function better_supabase.maintenance_schedule(text) from public, anon, authenticated;
grant execute on function better_supabase.maintenance_schedule(text) to service_role;
revoke execute on function better_supabase.maintenance_scheduler() from public, anon, authenticated;
grant execute on function better_supabase.maintenance_scheduler() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block-data housekeeping
-- @bsb-hash sha256:6a87df78cad56be6b8e3240ea5ddeafcaac1a50276e719091119cd1fef511897
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block housekeeping@1 managed
-- @bsb-hash sha256:9fcf1daa1850d5f6abd3cceec237cc293679e2db3318f1e7e251cdc004c0b07d
-- One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One row per job the dispatcher ran: when, with what result, and how often.
create table if not exists "better_supabase"."maintenance_state" (
  "job" text primary key,
  "last_run_at" timestamptz,
  "last_status" text check ("last_status" in ('ok', 'error')),
  "last_result" jsonb,
  "last_error" text,
  "runs" bigint not null default 0
);
alter table "better_supabase"."maintenance_state" enable row level security;
revoke all on "better_supabase"."maintenance_state" from public, anon, authenticated;
grant all on "better_supabase"."maintenance_state" to service_role;

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' `housekeeping` contributions.
create or replace view "better_supabase"."maintenance_jobs" with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s."last_run_at" as last_run_at, s."last_status" as last_status, s."last_error" as last_error,
  coalesce(s."runs", 0) as runs,
  (s."last_run_at" is null or s."last_run_at" + j.every_interval <= now()) as due
from (select null::text, null::text, null::interval where false) j (job, fn, every_interval)
left join "better_supabase"."maintenance_state" s on s."job" = j.job;
revoke all on "better_supabase"."maintenance_jobs" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_jobs" to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function "better_supabase"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "better_supabase"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function "better_supabase"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "better_supabase"."maintenance"()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function "better_supabase"."maintenance_scheduler"()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

revoke execute on function better_supabase.maintenance(text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.maintenance(text, boolean) to service_role;
revoke execute on function better_supabase.maintenance_schedule(text) from public, anon, authenticated;
grant execute on function better_supabase.maintenance_schedule(text) to service_role;
revoke execute on function better_supabase.maintenance_scheduler() from public, anon, authenticated;
grant execute on function better_supabase.maintenance_scheduler() to service_role;

-- blocks.housekeeping.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."maintenance"($1, $2) $$;
revoke execute on function "api"."maintenance"(text, boolean) from public, anon, authenticated;
grant execute on function "api"."maintenance"(text, boolean) to service_role;

create or replace function "api"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."maintenance_schedule"($1) $$;
revoke execute on function "api"."maintenance_schedule"(text) from public, anon, authenticated;
grant execute on function "api"."maintenance_schedule"(text) to service_role;

create or replace function "api"."maintenance_scheduler"()
returns text
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."maintenance_scheduler"() $$;
revoke execute on function "api"."maintenance_scheduler"() from public, anon, authenticated;
grant execute on function "api"."maintenance_scheduler"() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block-data housekeeping
-- @bsb-hash sha256:6a87df78cad56be6b8e3240ea5ddeafcaac1a50276e719091119cd1fef511897
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block housekeeping@1 managed
-- @bsb-hash sha256:3760b94fc58737da1e65cf87f7a0883c70492d6aefc0c9ad3cd274fc60abd415
-- One dispatcher for the recurring cleanups the installed blocks contribute (purges, expiries): maintenance() runs each due job and records its outcome, and maintenance_schedule() registers it with pg_cron.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;

-- One row per job the dispatcher ran: when, with what result, and how often.
-- better_supabase.maintenance_state is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."maintenance_state" add column if not exists "job" text;
alter table "better_supabase"."maintenance_state" add column if not exists "last_run_at" timestamptz;
alter table "better_supabase"."maintenance_state" add column if not exists "last_status" text check ("last_status" in ('ok', 'error'));
alter table "better_supabase"."maintenance_state" add column if not exists "last_result" jsonb;
alter table "better_supabase"."maintenance_state" add column if not exists "last_error" text;
alter table "better_supabase"."maintenance_state" add column if not exists "runs" bigint not null default 0;
alter table "better_supabase"."maintenance_state" enable row level security;
grant all on "better_supabase"."maintenance_state" to service_role;

-- The jobs the installed blocks contribute, with when each last ran and
-- whether it is due. Rendered from the blocks' `housekeeping` contributions.
create or replace view "better_supabase"."maintenance_jobs" with (security_invoker = true) as
select j.job, j.fn as function, j.every_interval as every,
  s."last_run_at" as last_run_at, s."last_status" as last_status, s."last_error" as last_error,
  coalesce(s."runs", 0) as runs,
  (s."last_run_at" is null or s."last_run_at" + j.every_interval <= now()) as due
from (select null::text, null::text, null::interval where false) j (job, fn, every_interval)
left join "better_supabase"."maintenance_state" s on s."job" = j.job;
revoke all on "better_supabase"."maintenance_jobs" from public, anon, authenticated;
grant select on "better_supabase"."maintenance_jobs" to service_role;

-- Runs every due job (or the one named, whether due or not, when job_name is set;
-- force_run runs due-or-not jobs) and records each outcome. One failing job never
-- stops the rest. Returns [{ job, status, result | error }]. Overlapping calls
-- skip: the second returns an empty list.
create or replace function "better_supabase"."maintenance"(job_name text default null, force_run boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_job record;
  v_result jsonb;
  v_out jsonb := '[]'::jsonb;
begin
  if not pg_catalog.pg_try_advisory_xact_lock(pg_catalog.hashtext('better_supabase.maintenance')) then
    return v_out;
  end if;
  for v_job in
    select j.job, j.function from "better_supabase"."maintenance_jobs" j
    where (maintenance.job_name is null and (maintenance.force_run or j.due)) or j.job = maintenance.job_name
    order by j.job
  loop
    begin
      execute pg_catalog.format('select pg_catalog.to_jsonb(%s())', v_job.function) into v_result;
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'ok', v_result, null, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'ok',
        "last_result" = excluded."last_result", "last_error" = null, "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'ok', 'result', v_result));
    exception when others then
      insert into "better_supabase"."maintenance_state" ("job", "last_run_at", "last_status", "last_result", "last_error", "runs")
      values (v_job.job, now(), 'error', null, sqlerrm, 1)
      on conflict ("job") do update set "last_run_at" = now(), "last_status" = 'error',
        "last_result" = null, "last_error" = excluded."last_error", "runs" = "better_supabase"."maintenance_state"."runs" + 1;
      v_out := v_out || pg_catalog.jsonb_build_array(pg_catalog.jsonb_build_object('job', v_job.job, 'status', 'error', 'error', sqlerrm));
    end;
  end loop;
  return v_out;
end;
$$;

-- Registers one pg_cron job that calls maintenance(), and returns 'pg_cron',
-- or returns 'none' when pg_cron isn't installed so the app can call
-- maintenance() from its own scheduler (a cron route, the queue worker).
create or replace function "better_supabase"."maintenance_schedule"(cron_schedule text default '*/5 * * * *')
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_schedule regprocedure := pg_catalog.to_regprocedure('cron.schedule(text, text, text)');
begin
  if v_schedule is null then
    return 'none';
  end if;
  execute pg_catalog.format('select cron.schedule(%L, %L, %L)', 'better-supabase-maintenance', maintenance_schedule.cron_schedule, 'select "better_supabase"."maintenance"()');
  return 'pg_cron';
end;
$$;

-- Which scheduler runs maintenance(): 'pg_cron' when the job is registered,
-- else 'none'. A 'none' answer with due jobs means nothing is running them.
create or replace function "better_supabase"."maintenance_scheduler"()
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_found boolean := false;
begin
  if pg_catalog.to_regclass('cron.job') is not null then
    execute 'select exists (select 1 from cron.job where jobname = ''better-supabase-maintenance'')' into v_found;
  end if;
  return case when v_found then 'pg_cron' else 'none' end;
end;
$$;

revoke execute on function better_supabase.maintenance(text, boolean) from public, anon, authenticated;
grant execute on function better_supabase.maintenance(text, boolean) to service_role;
revoke execute on function better_supabase.maintenance_schedule(text) from public, anon, authenticated;
grant execute on function better_supabase.maintenance_schedule(text) to service_role;
revoke execute on function better_supabase.maintenance_scheduler() from public, anon, authenticated;
grant execute on function better_supabase.maintenance_scheduler() to service_role;

create schema if not exists better_supabase;
create table if not exists better_supabase.blocks (
  name text primary key,
  block text,
  version integer not null,
  mode text not null,
  installed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table better_supabase.blocks enable row level security;
revoke all on better_supabase.blocks from public, anon, authenticated;
grant select on better_supabase.blocks to service_role;

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_171_housekeeping.sql
-- better-supabase module: housekeeping
-- @bsb-block-data housekeeping
-- @bsb-hash sha256:6a87df78cad56be6b8e3240ea5ddeafcaac1a50276e719091119cd1fef511897
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('housekeeping', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
