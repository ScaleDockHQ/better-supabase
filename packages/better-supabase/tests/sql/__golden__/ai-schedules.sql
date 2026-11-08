-- ==== alone: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:508cce0f2a140a8a26796b7e92fd9b5c8f83712e9f7f991929f66512ce02bc33
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table "better_supabase"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid,
  "title" text not null constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "prompt" text not null constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000),
  "cron" text not null constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200),
  "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "tenant_id");
create index ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
revoke all on "better_supabase"."ai_scheduled_tasks" from public, anon, authenticated;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

create table "better_supabase"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_at" timestamptz not null,
  "chat_id" uuid,
  "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
revoke all on "better_supabase"."ai_task_runs" from public, anon, authenticated;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_read on "better_supabase"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not false
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not false
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
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
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
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
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
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
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_task_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_task_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_task_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_task_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== alone: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== with every module: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:4bfaaf274a3dd6a1ab15dec1b483e9826718055568d44df6db10a341f06455ec
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table "better_supabase"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid references "better_supabase"."agents" ("id") on delete set null,
  "title" text not null constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "prompt" text not null constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000),
  "cron" text not null constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200),
  "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "tenant_id");
create index ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
revoke all on "better_supabase"."ai_scheduled_tasks" from public, anon, authenticated;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

create table "better_supabase"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_at" timestamptz not null,
  "chat_id" uuid,
  "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
revoke all on "better_supabase"."ai_task_runs" from public, anon, authenticated;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_read on "better_supabase"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not exists (select 1 from "better_supabase"."ai_chats" c where c."id" = v_chat and c."owner_id" = v_row."user_id" and c."tenant_id" = v_row."tenant_id")
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not exists (select 1 from "better_supabase"."agents" g where g."id" = v_agent and g."tenant_id" = v_row."tenant_id" and (g."owner_id" = v_row."user_id" or g."published_at" is not null))
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
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
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
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
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    perform "better_supabase"."enqueue_job"(queue => 'ai_task_run', payload => jsonb_build_object('run_id', v_run."id"), dedupe_key => 'ai-task:' || v_run."id"::text, dedupe_running => false);
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
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
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_task_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_task_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_task_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_task_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- Row audit for the module's tables (blocks.audit.options.blockTables)
create constraint trigger bsb_audit after insert or update or delete on better_supabase.ai_scheduled_tasks deferrable initially deferred for each row execute function better_supabase.audit_row_change('{"ignore":[],"redact":[],"target_type":"ai_scheduled_task","event_prefix":"ai_scheduled_task"}');

-- ==== with every module: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== schema app_private: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:554f28aa6b6fed3f7d9eb330cc9126eb0aa0b283167482e2a6584213e02c9ecd
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create schema if not exists "app_private";
grant usage on schema "app_private" to anon, authenticated, service_role;
alter default privileges in schema "app_private" revoke all on tables from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on sequences from public, anon, authenticated;
alter default privileges in schema "app_private" revoke all on functions from public, anon, authenticated;
-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table "app_private"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid,
  "title" text not null constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "prompt" text not null constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000),
  "cron" text not null constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200),
  "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_scheduled_tasks_due_idx on "app_private"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index ai_scheduled_tasks_user_idx on "app_private"."ai_scheduled_tasks" ("user_id", "tenant_id");
create index ai_scheduled_tasks_agent_idx on "app_private"."ai_scheduled_tasks" ("agent_id");
alter table "app_private"."ai_scheduled_tasks" enable row level security;
revoke all on "app_private"."ai_scheduled_tasks" from public, anon, authenticated;
grant select on "app_private"."ai_scheduled_tasks" to authenticated;
grant all on "app_private"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_read on "app_private"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

create table "app_private"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "app_private"."ai_scheduled_tasks" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_at" timestamptz not null,
  "chat_id" uuid,
  "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index ai_task_runs_task_idx on "app_private"."ai_task_runs" ("task_id", "created_at" desc);
create index ai_task_runs_user_idx on "app_private"."ai_task_runs" ("user_id");
create index ai_task_runs_open_idx on "app_private"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "app_private"."ai_task_runs" enable row level security;
revoke all on "app_private"."ai_task_runs" from public, anon, authenticated;
grant select on "app_private"."ai_task_runs" to authenticated;
grant all on "app_private"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_read on "app_private"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

-- Creates (id null) or changes a task. Only the service role sets
-- next_run_at; for anyone else a new task, or a changed cron or timezone,
-- clears it and the scheduler computes the next occurrence on its next
-- tick. Pausing clears it, so a resumed task waits for its next occurrence.
-- chat_id must be a chat of the task's user in the tenant, and agent_id an
-- agent of the tenant that user owns or that is published.
create or replace function "app_private"."save_ai_task"(tenant uuid, id uuid default null, fields jsonb default '{}', next_run_at timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := save_ai_task.id;
  v_row "app_private"."ai_scheduled_tasks"%rowtype;
  v_service boolean := coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin');
  v_chat uuid;
  v_agent uuid;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "app_private"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "app_private"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not false
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not false
  then
    raise exception 'agent % is not an agent this task''s user may use', v_agent using errcode = '42501', hint = 'AI_TASK_AGENT_FORBIDDEN';
  end if;
  update "app_private"."ai_scheduled_tasks" x set
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
end;
$$;
revoke execute on function "app_private"."save_ai_task"(uuid, uuid, jsonb, timestamptz) from public, anon;
grant execute on function "app_private"."save_ai_task"(uuid, uuid, jsonb, timestamptz) to authenticated, service_role;

create or replace function "app_private"."delete_ai_task"(id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := delete_ai_task.id;
  v_row "app_private"."ai_scheduled_tasks"%rowtype;
begin
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "app_private"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "app_private"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "app_private"."delete_ai_task"(uuid) from public, anon;
grant execute on function "app_private"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "app_private"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "app_private"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "app_private"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
$$;
revoke execute on function "app_private"."list_ai_tasks"(uuid, boolean) from public, anon;
grant execute on function "app_private"."list_ai_tasks"(uuid, boolean) to authenticated, service_role;

create or replace function "app_private"."list_ai_task_runs"(task_id uuid, max_rows integer default 20)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
  from (
    select * from "app_private"."ai_task_runs" y0 where y0."task_id" = list_ai_task_runs.task_id
    order by y0."created_at" desc limit least(greatest(list_ai_task_runs.max_rows, 1), 200)
  ) y
$$;
revoke execute on function "app_private"."list_ai_task_runs"(uuid, integer) from public, anon;
grant execute on function "app_private"."list_ai_task_runs"(uuid, integer) to authenticated, service_role;

-- Claims due tasks (service role): queues a run for each, clears its
-- next_run_at until the scheduler sets the next one, fails runs that ran, or
-- waited in the queue, longer than 30 minutes, and returns the runs and
-- the enabled tasks that need a next_run_at.
create or replace function "app_private"."claim_due_ai_tasks"(batch integer default 50)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task "app_private"."ai_scheduled_tasks"%rowtype;
  v_run "app_private"."ai_task_runs"%rowtype;
  v_runs jsonb := '[]';
  v_unscheduled jsonb;
begin
  update "app_private"."ai_task_runs" y set "status" = 'failed', "error" = 'timed out', "finished_at" = now()
  where (y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes');
  for v_task in
    select * from "app_private"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "app_private"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "app_private"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
  end loop;
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'cron', x."cron", 'timezone', x."timezone")), '[]')
  into v_unscheduled
  from "app_private"."ai_scheduled_tasks" x where x."enabled" and x."next_run_at" is null;
  return jsonb_build_object('runs', v_runs, 'unscheduled', v_unscheduled);
end;
$$;
revoke execute on function "app_private"."claim_due_ai_tasks"(integer) from public, anon, authenticated;
grant execute on function "app_private"."claim_due_ai_tasks"(integer) to service_role;

-- Sets next_run_at for tasks: items is { "items": [{ "id", "next_run_at" }] } (service role).
create or replace function "app_private"."schedule_ai_tasks"(items jsonb)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_items jsonb := case when jsonb_typeof(schedule_ai_tasks.items) = 'object' then schedule_ai_tasks.items -> 'items' else schedule_ai_tasks.items end;
  v_count integer;
begin
  update "app_private"."ai_scheduled_tasks" x set "next_run_at" = (item ->> 'next_run_at')::timestamptz
  from jsonb_array_elements(case when jsonb_typeof(v_items) = 'array' then v_items else '[]' end) item
  where x."id" = (item ->> 'id')::uuid and x."enabled" and x."next_run_at" is null;
  get diagnostics v_count = row_count;
  return v_count;
end;
$$;
revoke execute on function "app_private"."schedule_ai_tasks"(jsonb) from public, anon, authenticated;
grant execute on function "app_private"."schedule_ai_tasks"(jsonb) to service_role;

-- Moves a queued run to running and returns it with its task, or null when
-- another worker took it (service role).
create or replace function "app_private"."start_ai_task_run"(id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_run "app_private"."ai_task_runs"%rowtype;
  v_task "app_private"."ai_scheduled_tasks"%rowtype;
begin
  update "app_private"."ai_task_runs" y set "status" = 'running', "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "app_private"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
end;
$$;
revoke execute on function "app_private"."start_ai_task_run"(uuid) from public, anon, authenticated;
grant execute on function "app_private"."start_ai_task_run"(uuid) to service_role;

-- Finishes a running run (service role); chat_id records the chat it wrote to.
create or replace function "app_private"."finish_ai_task_run"(id uuid, succeeded boolean, error text default null, chat_id uuid default null)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_task uuid;
begin
  update "app_private"."ai_task_runs" y set
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
    update "app_private"."ai_scheduled_tasks" x set "chat_id" = finish_ai_task_run.chat_id where x."id" = v_task and x."chat_id" is null;
  end if;
  return true;
end;
$$;
revoke execute on function "app_private"."finish_ai_task_run"(uuid, boolean, text, uuid) from public, anon, authenticated;
grant execute on function "app_private"."finish_ai_task_run"(uuid, boolean, text, uuid) to service_role;

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "app_private"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "app_private"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "app_private"."ai_task_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "app_private"."ai_task_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "app_private"."ai_task_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "app_private"."ai_task_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== schema app_private: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== api schema: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:a26594579ab806a985b4e2737d11039302b5eb33fd7f0919508cf96bfe5d7e34
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table "better_supabase"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid,
  "title" text not null constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "prompt" text not null constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000),
  "cron" text not null constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200),
  "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "tenant_id");
create index ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
revoke all on "better_supabase"."ai_scheduled_tasks" from public, anon, authenticated;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

create table "better_supabase"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade,
  "tenant_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_at" timestamptz not null,
  "chat_id" uuid,
  "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
revoke all on "better_supabase"."ai_task_runs" from public, anon, authenticated;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_read on "better_supabase"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not false
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not false
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
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
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
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
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
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
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_task_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_task_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_task_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_task_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- blocks.ai-schedules.api: entry points for the Data API.
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
stable
security invoker
set search_path = ''
as $$ select "better_supabase"."list_ai_tasks"($1, $2) $$;
revoke execute on function "api"."list_ai_tasks"(uuid, boolean) from public, anon;
grant execute on function "api"."list_ai_tasks"(uuid, boolean) to authenticated, service_role;

create or replace function "api"."list_ai_task_runs"(task_id uuid, max_rows integer default 20)
returns jsonb
language sql
stable
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

-- ==== api schema: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== over the app's tables: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:288aedbb80ef11c9823a9fe67f155212c90f3ef408ae91a7b98975dc09ef9ade
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
-- better_supabase.ai_scheduled_tasks is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "chat_id" uuid;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "agent_id" uuid;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "title" text constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200);
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "prompt" text constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000);
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "cron" text constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200);
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64);
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "enabled" boolean not null default true;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "next_run_at" timestamptz;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "last_run_at" timestamptz;
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "created_at" timestamptz not null default now();
alter table "better_supabase"."ai_scheduled_tasks" add column if not exists "updated_at" timestamptz not null default now();
create index if not exists ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index if not exists ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "tenant_id");
create index if not exists ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_select on "better_supabase"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

-- better_supabase.ai_task_runs is the app's table: this block adds only the columns it needs.
alter table "better_supabase"."ai_task_runs" add column if not exists "id" uuid default gen_random_uuid();
alter table "better_supabase"."ai_task_runs" add column if not exists "task_id" uuid references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade;
alter table "better_supabase"."ai_task_runs" add column if not exists "tenant_id" uuid;
alter table "better_supabase"."ai_task_runs" add column if not exists "user_id" uuid references auth.users (id) on delete cascade;
alter table "better_supabase"."ai_task_runs" add column if not exists "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed'));
alter table "better_supabase"."ai_task_runs" add column if not exists "scheduled_at" timestamptz;
alter table "better_supabase"."ai_task_runs" add column if not exists "chat_id" uuid;
alter table "better_supabase"."ai_task_runs" add column if not exists "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000);
alter table "better_supabase"."ai_task_runs" add column if not exists "started_at" timestamptz;
alter table "better_supabase"."ai_task_runs" add column if not exists "finished_at" timestamptz;
alter table "better_supabase"."ai_task_runs" add column if not exists "created_at" timestamptz not null default now();
create index if not exists ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index if not exists ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index if not exists ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_select on "better_supabase"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("tenant_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."tenant_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not false
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not false
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."tenant_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."tenant_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."tenant_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."tenant_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
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
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."tenant_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
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
  update "better_supabase"."ai_task_runs" y set "status" = better_supabase.as_column_type('failed', (null::"better_supabase"."ai_task_runs")."status"), "error" = 'timed out', "finished_at" = now()
  where (y."status" = 'running' and y."started_at" < now() - interval '30 minutes')
     or (y."status" = 'queued' and y."created_at" < now() - interval '30 minutes');
  for v_task in
    select * from "better_supabase"."ai_scheduled_tasks" x
    where x."enabled" and x."next_run_at" <= now()
    order by x."next_run_at"
    limit least(greatest(claim_due_ai_tasks.batch, 1), 500)
    for update skip locked
  loop
    insert into "better_supabase"."ai_task_runs" ("task_id", "tenant_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."tenant_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
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
  update "better_supabase"."ai_task_runs" y set "status" = better_supabase.as_column_type('running', (null::"better_supabase"."ai_task_runs")."status"), "started_at" = now()
  where y."id" = start_ai_task_run.id and y."status" = 'queued'
  returning * into v_run;
  if not found then
    return null;
  end if;
  select * into v_task from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_run."task_id";
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."tenant_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."tenant_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
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
    "status" = better_supabase.as_column_type(case when finish_ai_task_run.succeeded then 'completed' else 'failed' end, (null::"better_supabase"."ai_task_runs")."status"),
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_task_runs" as restrictive
  for select to public
  using (
    "tenant_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "tenant_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_task_runs" as restrictive
  for insert to public
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_task_runs" as restrictive
  for update to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()))
  with check ("tenant_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_task_runs" as restrictive
  for delete to public
  using ("tenant_id" in (select better_supabase.member_organization_ids()));

-- ==== over the app's tables: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();

-- ==== tenant column renamed: schema supabase/schemas/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block ai-schedules@2 managed
-- @bsb-hash sha256:bce253fe6d2570251f10e1a5653578720640a00df388b8e0d1f373d07d39a191
-- Prompts a user schedules on a cron, with a run per occurrence; the scheduler claims due tasks, queues an ai_task_run job when jobs is installed, and fails runs that stall.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Prompts a user schedules to run on a cron. next_run_at is computed by the
-- application from cron and timezone; a null next_run_at on an enabled task
-- means it waits for the scheduler to compute it.
create table "better_supabase"."ai_scheduled_tasks" (
  "id" uuid primary key default gen_random_uuid(),
  "org_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "agent_id" uuid,
  "title" text not null constraint bsb_ai_scheduled_tasks_title_check check (length("title") >= 1 and length("title") <= 200),
  "prompt" text not null constraint bsb_ai_scheduled_tasks_prompt_check check (length("prompt") >= 1 and length("prompt") <= 20000),
  "cron" text not null constraint bsb_ai_scheduled_tasks_cron_check check (length("cron") >= 1 and length("cron") <= 200),
  "timezone" text not null default 'UTC' constraint bsb_ai_scheduled_tasks_timezone_check check (length("timezone") >= 1 and length("timezone") <= 64),
  "enabled" boolean not null default true,
  "next_run_at" timestamptz,
  "last_run_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now()
);
create index ai_scheduled_tasks_due_idx on "better_supabase"."ai_scheduled_tasks" ("next_run_at") where "enabled";
create index ai_scheduled_tasks_user_idx on "better_supabase"."ai_scheduled_tasks" ("user_id", "org_id");
create index ai_scheduled_tasks_agent_idx on "better_supabase"."ai_scheduled_tasks" ("agent_id");
alter table "better_supabase"."ai_scheduled_tasks" enable row level security;
revoke all on "better_supabase"."ai_scheduled_tasks" from public, anon, authenticated;
grant select on "better_supabase"."ai_scheduled_tasks" to authenticated;
grant all on "better_supabase"."ai_scheduled_tasks" to service_role;
create policy bsb_ai_scheduled_tasks_read on "better_supabase"."ai_scheduled_tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

create table "better_supabase"."ai_task_runs" (
  "id" uuid primary key default gen_random_uuid(),
  "task_id" uuid not null references "better_supabase"."ai_scheduled_tasks" ("id") on delete cascade,
  "org_id" uuid not null,
  "user_id" uuid not null references auth.users (id) on delete cascade,
  "status" text not null default 'queued' constraint bsb_ai_task_runs_status_check check ("status" in ('queued', 'running', 'completed', 'failed')),
  "scheduled_at" timestamptz not null,
  "chat_id" uuid,
  "error" text constraint bsb_ai_task_runs_error_check check (length("error") <= 4000),
  "started_at" timestamptz,
  "finished_at" timestamptz,
  "created_at" timestamptz not null default now()
);
create index ai_task_runs_task_idx on "better_supabase"."ai_task_runs" ("task_id", "created_at" desc);
create index ai_task_runs_user_idx on "better_supabase"."ai_task_runs" ("user_id");
create index ai_task_runs_open_idx on "better_supabase"."ai_task_runs" ("status", "started_at") where "status" in ('queued', 'running');
alter table "better_supabase"."ai_task_runs" enable row level security;
revoke all on "better_supabase"."ai_task_runs" from public, anon, authenticated;
grant select on "better_supabase"."ai_task_runs" to authenticated;
grant all on "better_supabase"."ai_task_runs" to service_role;
create policy bsb_ai_task_runs_read on "better_supabase"."ai_task_runs"
  for select to authenticated
  using ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')));

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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
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
    if not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(better_supabase.can('tenant', save_ai_task.tenant, 'ai_schedules.write'), false)) or auth.uid() is null then
      raise exception 'you may not schedule tasks here' using errcode = '42501', hint = 'AI_TASK_FORBIDDEN';
    end if;
    insert into "better_supabase"."ai_scheduled_tasks" ("org_id", "user_id", "title", "prompt", "cron")
    values (save_ai_task.tenant, auth.uid(), save_ai_task.fields ->> 'title', save_ai_task.fields ->> 'prompt', save_ai_task.fields ->> 'cron')
    returning * into v_row;
  else
    select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id and x."org_id" = save_ai_task.tenant for update;
    if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'ai_schedules.manage'), false)) then
      raise exception 'task % not found', v_id using errcode = 'P0002', hint = 'AI_TASK_NOT_FOUND';
    end if;
  end if;
  v_chat := (save_ai_task.fields ->> 'chat_id')::uuid;
  if v_chat is not null and not v_service and not false
  then
    raise exception 'chat % is not a chat of this task''s user', v_chat using errcode = '42501', hint = 'AI_TASK_CHAT_FORBIDDEN';
  end if;
  v_agent := (save_ai_task.fields ->> 'agent_id')::uuid;
  if v_agent is not null and not v_service and not false
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
  return jsonb_build_object('id', v_row."id", 'tenant_id', v_row."org_id", 'user_id', v_row."user_id", 'chat_id', v_row."chat_id", 'agent_id', v_row."agent_id", 'title', v_row."title", 'prompt', v_row."prompt", 'cron', v_row."cron", 'timezone', v_row."timezone", 'enabled', v_row."enabled", 'next_run_at', v_row."next_run_at", 'last_run_at', v_row."last_run_at", 'created_at', v_row."created_at", 'updated_at', v_row."updated_at");
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
  if not (better_supabase.actor_may_write()) then
    raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
  end if;
  select * into v_row from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id for update;
  if not found or not (coalesce(nullif((select auth.jwt()) ->> 'role', ''), session_user::text) in ('service_role', 'postgres', 'supabase_admin') or coalesce(v_row."user_id" = auth.uid(), false) or coalesce(better_supabase.can('tenant', v_row."org_id", 'ai_schedules.manage'), false)) then
    return false;
  end if;
  delete from "better_supabase"."ai_scheduled_tasks" x where x."id" = v_id;
  return true;
end;
$$;
revoke execute on function "better_supabase"."delete_ai_task"(uuid) from public, anon;
grant execute on function "better_supabase"."delete_ai_task"(uuid) to authenticated, service_role;

-- The caller's tasks in a tenant (or every task, for 'ai_schedules.manage').
create or replace function "better_supabase"."list_ai_tasks"(tenant uuid, mine boolean default true)
returns jsonb
language sql
stable
security invoker
set search_path = ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', x."id", 'tenant_id', x."org_id", 'user_id', x."user_id", 'chat_id', x."chat_id", 'agent_id', x."agent_id", 'title', x."title", 'prompt', x."prompt", 'cron', x."cron", 'timezone', x."timezone", 'enabled', x."enabled", 'next_run_at', x."next_run_at", 'last_run_at', x."last_run_at", 'created_at', x."created_at", 'updated_at', x."updated_at") || jsonb_build_object('last_run', (
    select jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."org_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") from "better_supabase"."ai_task_runs" y where y."task_id" = x."id" order by y."created_at" desc limit 1
  )) order by x."created_at" desc), '[]')
  from "better_supabase"."ai_scheduled_tasks" x
  where x."org_id" = list_ai_tasks.tenant and (not list_ai_tasks.mine or x."user_id" = auth.uid())
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
  select coalesce(jsonb_agg(jsonb_build_object('id', y."id", 'task_id', y."task_id", 'tenant_id', y."org_id", 'user_id', y."user_id", 'status', y."status", 'scheduled_at', y."scheduled_at", 'chat_id', y."chat_id", 'error', y."error", 'started_at', y."started_at", 'finished_at', y."finished_at", 'created_at', y."created_at") order by y."created_at" desc), '[]')
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
    insert into "better_supabase"."ai_task_runs" ("task_id", "org_id", "user_id", "scheduled_at", "chat_id")
    values (v_task."id", v_task."org_id", v_task."user_id", v_task."next_run_at", v_task."chat_id")
    returning * into v_run;
    update "better_supabase"."ai_scheduled_tasks" x set "next_run_at" = null, "last_run_at" = now() where x."id" = v_task."id";
    v_runs := v_runs || jsonb_build_array(jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."org_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at"));
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
  return jsonb_build_object('id', v_run."id", 'task_id', v_run."task_id", 'tenant_id', v_run."org_id", 'user_id', v_run."user_id", 'status', v_run."status", 'scheduled_at', v_run."scheduled_at", 'chat_id', v_run."chat_id", 'error', v_run."error", 'started_at', v_run."started_at", 'finished_at', v_run."finished_at", 'created_at', v_run."created_at") || jsonb_build_object('task', jsonb_build_object('id', v_task."id", 'tenant_id', v_task."org_id", 'user_id', v_task."user_id", 'chat_id', v_task."chat_id", 'agent_id', v_task."agent_id", 'title', v_task."title", 'prompt', v_task."prompt", 'cron', v_task."cron", 'timezone', v_task."timezone", 'enabled', v_task."enabled", 'next_run_at', v_task."next_run_at", 'last_run_at', v_task."last_run_at", 'created_at', v_task."created_at", 'updated_at', v_task."updated_at"));
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

-- Tenant isolation (ADR 0099): permissive policies combine with or, so one
-- the app adds would widen the block's. These restrictive policies keep each
-- table to the caller's organizations and what the block's policies grant.
create policy bsb_tenant_scope_select on "better_supabase"."ai_scheduled_tasks" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_scheduled_tasks" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_scheduled_tasks" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_scheduled_tasks" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_select on "better_supabase"."ai_task_runs" as restrictive
  for select to public
  using (
    "org_id" in (select better_supabase.member_organization_ids())
    or ("user_id" = (select auth.uid()) or "org_id" in (select better_supabase.tenant_ids_with('ai_schedules.manage')))
  );
create policy bsb_tenant_scope_insert on "better_supabase"."ai_task_runs" as restrictive
  for insert to public
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_update on "better_supabase"."ai_task_runs" as restrictive
  for update to public
  using ("org_id" in (select better_supabase.member_organization_ids()))
  with check ("org_id" in (select better_supabase.member_organization_ids()));
create policy bsb_tenant_scope_delete on "better_supabase"."ai_task_runs" as restrictive
  for delete to public
  using ("org_id" in (select better_supabase.member_organization_ids()));

-- ==== tenant column renamed: data supabase/better-supabase-data/900_better_supabase_053_ai_schedules.sql
-- better-supabase module: ai-schedules
-- @bsb-block-data ai-schedules
-- @bsb-hash sha256:43de88ba0dbb65c1156d816eb749533bf1807cd81b507d4dcf3059b78c44d38f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-schedules', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
