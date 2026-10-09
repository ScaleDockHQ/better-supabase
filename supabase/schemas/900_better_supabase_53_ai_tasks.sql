-- better-supabase module: ai-tasks (0.5.1)
-- @bs-module ai-tasks@2 managed
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase sql add`; re-running it overwrites this file.
-- Change it through `sql.modules` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists better_supabase;
grant usage on schema better_supabase to anon, authenticated, service_role;
-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table if not exists "better_supabase"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid references "better_supabase"."agents" ("id") on delete set null,
  "title" text not null check (length("title") between 1 and 200),
  "prompt" text not null check (length("prompt") between 1 and 20000),
  "cron" text not null check (length("cron") between 1 and 200),
  "timezone" text not null default 'UTC' check (length("timezone") between 1 and 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index if not exists ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index if not exists ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "organization_id");
create index if not exists ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
revoke all on "better_supabase"."ai_scheduled_tasks" from anon, authenticated;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
drop policy if exists ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks";
create policy ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai.admin')));

create table if not exists "better_supabase"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade,
  "organization_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_for" timestamptz not null,
  "chat_id" uuid,
  "error" text check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index if not exists ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index if not exists ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index if not exists ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
revoke all on "better_supabase"."ai_task_runs" from anon, authenticated;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
drop policy if exists ai_task_runs_read on "better_supabase"."ai_task_runs";
create policy ai_task_runs_read on "better_supabase"."ai_task_runs" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai.admin')));

-- Creates (id null) or changes a task. Only the service role sets
-- next_run_at; for anyone else a new task, or a changed cron or timezone,
-- clears it and the scheduler computes the next occurrence on its next
-- tick. Pausing clears it, so a resumed task waits for its next occurrence.
-- chat_id must be a chat of the task's user in the tenant, and agent_id an
-- agent of the tenant that user owns or that is published.
create or replace function "better_supabase"."save_ai_task"(tenant uuid, id uuid default null, fields jsonb default '{}', next_run_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_chat uuid;
  v_agent uuid;
begin
  if jsonb_typeof(save_ai_task.fields) is distinct from 'object' then
    raise exception 'fields must be an object' using errcode = '22023', hint = 'AI_TASK_INVALID';
  end if;
  if save_ai_task.fields ? 'timezone' then
    begin
      perform now() at time zone (save_ai_task.fields ->> 'timezone');
    exception when others then
      raise exception '% is not a time zone', save_ai_task.fields ->> 'timezone' using errcode = '22023', hint = 'AI_TASK_INVALID';
    end;
  end if;
  if v_id is null then
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai.create'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("organization_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."organization_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not exists (select 1 from "better_supabase"."ai_chats" c where c."id" = v_chat and c."owner_id" = v_row."user_id" and c."organization_id" = v_row."organization_id")
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not exists (select 1 from "better_supabase"."agents" g where g."id" = v_agent and g."organization_id" = v_row."organization_id" and (g."owner_id" = v_row."user_id" or g."published_at" is not null))
  then
    raise exception 'agent % is not an agent this task''s user may use', v_agent using errcode = '42501', hint = 'AI_TASK_AGENT_FORBIDDEN';
  end if;
  update "better_supabase"."ai_scheduled_tasks" x set
    "title" = coalesce(save_ai_task.fields ->> 'title', x."title"),
    "prompt" = coalesce(save_ai_task.fields ->> 'prompt', x."prompt"),
    "cron" = coalesce(save_ai_task.fields ->> 'cron', x."cron"),
    "timezone" = coalesce(save_ai_task.fields ->> 'timezone', x."timezone"),
    "chat_id" = case when save_ai_task.fields ? 'chat_id' then (save_ai_task.fields ->> 'chat_id')::uuid else x."chat_id" end,
    "agent_id" = case when save_ai_task.fields ? 'agent_id' then (save_ai_task.fields ->> 'agent_id')::uuid else x."agent_id" end,
    "enabled" = coalesce((save_ai_task.fields ->> 'enabled')::boolean, x."enabled"),
    "next_run_at" = case
      when (save_ai_task.fields ->> 'enabled')::boolean is false then null
      when v_service and (save_ai_task.next_run_at is not null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone') then save_ai_task.next_run_at
      when save_ai_task.id is null or save_ai_task.fields ? 'cron' or save_ai_task.fields ? 'timezone' then null
      else x."next_run_at" end,
    "updated_at" = now()
  where x."id" = v_row."id"
  returning * into v_row;
  return jsonb_build_object('id', v_row."id", 'organization_id', v_row."organization_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "better_supabase"."save_ai_task"(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function "better_supabase"."save_ai_task"(uuid, uuid, jsonb, timestamptz) to authenticated, service_role;

create or replace function "better_supabase"."delete_ai_task"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_ai_task.id;
  v_row "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or v_row."user_id" = auth.uid() or coalesce(better_supabase.can('tenant', v_row."organization_id", 'ai.admin'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai.admin').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'organization_id', x."organization_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_for', y."scheduled_for", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."organization_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
$$;
revoke execute on function "better_supabase"."list_ai_tasks"(uuid, boolean) from public, anon;
grant execute on function "better_supabase"."list_ai_tasks"(uuid, boolean) to authenticated, service_role;

create or replace function "better_supabase"."list_ai_task_runs"(task_id uuid, max_rows integer default 20)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'organization_id', y."organization_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_for', y."scheduled_for", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
  from (
    select * from "better_supabase"."ai_task_runs" y0 where y0."task_id" = list_ai_task_runs.task_id
    order by y0."created_at" desc limit least(greatest(list_ai_task_runs.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "better_supabase"."list_ai_task_runs"(uuid, integer) from public, anon;
grant execute on function "better_supabase"."list_ai_task_runs"(uuid, integer) to authenticated, service_role;

-- Claims due tasks (service role): queues a run for each, clears its
-- next_run_at until the scheduler sets the next one, fails runs that ran, or
-- waited in the queue, longer than 30 minutes, and returns the runs and
-- the enabled tasks that need a next_run_at.
create or replace function "better_supabase"."claim_due_ai_tasks"(batch integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'failed', "error" = 'timed out', "finished_at" = now()
  where (y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes');
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "organization_id", "user_id", "scheduled_for", "chat_id")
    values (v_task."id", v_task."organization_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_for', v_run."scheduled_for", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "better_supabase"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null;
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$$;
revoke execute on function "better_supabase"."claim_due_ai_tasks"(integer) from public, anon, authenticated;
grant execute on function "better_supabase"."claim_due_ai_tasks"(integer) to service_role;

-- Sets next_run_at for tasks: items is { "items": [{ "id", "next_run_at" }] } (service role).
create or replace function "better_supabase"."schedule_ai_tasks"(items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items jsonb := case when jsonb_typeof(schedule_ai_tasks.items) = 'object' then schedule_ai_tasks.items -> 'items' else schedule_ai_tasks.items end;
  v_count integer;
begin
  update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = (item ->> 'next_run_at')::timestamptz
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  where x."id" = (item ->> 'id')::uuid and x."enabled" and x."next_run_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "better_supabase"."schedule_ai_tasks"(jsonb) from public, anon, authenticated;
grant execute on function "better_supabase"."schedule_ai_tasks"(jsonb) to service_role;

-- Moves a queued run to running and returns it with its task, or null when
-- another worker took it (service role).
create or replace function "better_supabase"."start_ai_task_run"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run "better_supabase"."ai_task_runs"%rowtype;
  v_task "better_supabase"."ai_scheduled_tasks"%rowtype;
begin
  update "better_supabase"."ai_task_runs" y set "status" = 'running', "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'organization_id', v_run."organization_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_for', v_run."scheduled_for", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'organization_id', v_task."organization_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
end;
$$;
revoke execute on function "better_supabase"."start_ai_task_run"(uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."start_ai_task_run"(uuid) to service_role;

-- Finishes a running run (service role); chat_id records the chat it wrote to.
create or replace function "better_supabase"."finish_ai_task_run"(id uuid, succeeded boolean, error text default null, chat_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task uuid;
begin
  update "better_supabase"."ai_task_runs" y set
    "status" = case when finish_ai_task_run.succeeded then 'completed' else 'failed' end,
    "error" = left(finish_ai_task_run.error, 4000),
    "chat_id" = coalesce(finish_ai_task_run.chat_id, y."chat_id"),
    "finished_at" = now()
  where y."id" = finish_ai_task_run.id and y."status" = 'running'
  returning y."task_id" into v_task;
  if not found then
    return false;
  end if;
  if finish_ai_task_run.chat_id is not null then
    update "better_supabase"."ai_scheduled_tasks" x set "chat_id" = finish_ai_task_run.chat_id where x."id" = v_task and x."chat_id" is null;
  end if;
  return true;
end;
$$;
revoke execute on function "better_supabase"."finish_ai_task_run"(uuid, boolean, text, uuid) from public, anon, authenticated;
grant execute on function "better_supabase"."finish_ai_task_run"(uuid, boolean, text, uuid) to service_role;

-- sql.modules.ai-tasks.api: entry points for the Data API.
create schema if not exists "api";
grant usage on schema "api" to anon, authenticated, service_role;

create or replace function "api"."save_ai_task"(tenant uuid, id uuid default null, fields jsonb default '{}', next_run_at timestamptz default null)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."save_ai_task"($1, $2, $3, $4) $$;
revoke execute on function "api"."save_ai_task"(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function "api"."save_ai_task"(uuid, uuid, jsonb, timestamptz) to authenticated, service_role;

create or replace function "api"."delete_ai_task"(id uuid)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."delete_ai_task"($1) $$;
revoke execute on function "api"."delete_ai_task"(uuid) from public, anon;
grant execute on function "api"."delete_ai_task"(uuid) to authenticated, service_role;

create or replace function "api"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_tasks"($1, $2) $$;
revoke execute on function "api"."list_ai_tasks"(uuid, boolean) from public, anon;
grant execute on function "api"."list_ai_tasks"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_ai_task_runs"(task_id uuid, max_rows integer default 20)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_task_runs"($1, $2) $$;
revoke execute on function "api"."list_ai_task_runs"(uuid, integer) from public, anon;
grant execute on function "api"."list_ai_task_runs"(uuid, integer) to authenticated, service_role;

create or replace function "api"."claim_due_ai_tasks"(batch integer default 50)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."claim_due_ai_tasks"($1) $$;
revoke execute on function "api"."claim_due_ai_tasks"(integer) from public, anon, authenticated;
grant execute on function "api"."claim_due_ai_tasks"(integer) to service_role;

create or replace function "api"."schedule_ai_tasks"(items jsonb)
returns integer
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."schedule_ai_tasks"($1) $$;
revoke execute on function "api"."schedule_ai_tasks"(jsonb) from public, anon, authenticated;
grant execute on function "api"."schedule_ai_tasks"(jsonb) to service_role;

create or replace function "api"."start_ai_task_run"(id uuid)
returns jsonb
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."start_ai_task_run"($1) $$;
revoke execute on function "api"."start_ai_task_run"(uuid) from public, anon, authenticated;
grant execute on function "api"."start_ai_task_run"(uuid) to service_role;

create or replace function "api"."finish_ai_task_run"(id uuid, succeeded boolean, error text default null, chat_id uuid default null)
returns boolean
language sql
security invoker
set search_path = ''
as $$ select "better_supabase"."finish_ai_task_run"($1, $2, $3, $4) $$;
revoke execute on function "api"."finish_ai_task_run"(uuid, boolean, text, uuid) from public, anon, authenticated;
grant execute on function "api"."finish_ai_task_run"(uuid, boolean, text, uuid) to service_role;

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
