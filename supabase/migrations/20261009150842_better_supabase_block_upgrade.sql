-- better-supabase sql upgrade: steps that run before the schema diff.

-- ai-chat: version 1 to 2. Runs end completed, failed or cancelled instead of done, error or stopped, and harness sessions keep their sandbox in ai_sandboxes, which ai-chat now owns, so one idle-stop claim covers every sandbox.
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."ai_runs"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'status'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_runs"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."ai_runs" add constraint "ai_runs_status_check" check ("status" in ('queued', 'running', 'cancel_requested', 'completed', 'failed', 'cancelled', 'done', 'error', 'stopped'));
update "better_supabase"."ai_runs" set "status" = case "status"
  when 'done' then 'completed' when 'error' then 'failed' else 'cancelled' end
where "status" in ('done', 'error', 'stopped');
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."ai_runs"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'status'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_runs"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."ai_runs" add constraint "ai_runs_status_check" check ("status" in ('queued', 'running', 'cancel_requested', 'completed', 'failed', 'cancelled'));
-- Sandboxes and provider containers a chat started, harness sessions'
-- included, so one idle-stop claim stops the ones nobody used for
-- idle_seconds or past expires_at.
create table if not exists "better_supabase"."ai_sandboxes" (
  "id" uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null,
  "user_id" uuid references auth.users (id) on delete cascade,
  "chat_id" uuid,
  "harness_id" text check (length("harness_id") between 1 and 200),
  "provider" text not null check ("provider" ~ '^[a-z0-9][a-z0-9._-]{0,63}$'),
  "sandbox_id" text not null check (length("sandbox_id") between 1 and 200),
  "container_id" text check (length("container_id") <= 200),
  "status" text not null default 'running' check ("status" in ('running', 'stopping', 'stopped')),
  "metadata" jsonb not null default '{}' check (jsonb_typeof("metadata") = 'object'),
  "idle_seconds" integer not null default 600 check ("idle_seconds" > 0),
  "error" text check (length("error") <= 4000),
  "last_used_at" timestamptz not null default now(),
  "expires_at" timestamptz,
  "stopped_at" timestamptz,
  "created_at" timestamptz not null default now(),
  "updated_at" timestamptz not null default now(),
  unique ("provider", "sandbox_id")
);
alter table "better_supabase"."ai_sandboxes" add column if not exists "harness_id" text check (length("harness_id") between 1 and 200);
create index if not exists ai_sandboxes_open_idx on "better_supabase"."ai_sandboxes" ("last_used_at") where "status" <> 'stopped';
create index if not exists ai_sandboxes_chat_idx on "better_supabase"."ai_sandboxes" ("chat_id");
create index if not exists ai_sandboxes_harness_idx on "better_supabase"."ai_sandboxes" ("chat_id", "harness_id") where "harness_id" is not null;
create index if not exists ai_sandboxes_tenant_idx on "better_supabase"."ai_sandboxes" ("organization_id");
create index if not exists ai_sandboxes_user_idx on "better_supabase"."ai_sandboxes" ("user_id");
alter table "better_supabase"."ai_sandboxes" enable row level security;
revoke all on "better_supabase"."ai_sandboxes" from anon, authenticated;
grant select on "better_supabase"."ai_sandboxes" to authenticated;
grant all on "better_supabase"."ai_sandboxes" to service_role;
drop policy if exists ai_sandboxes_read on "better_supabase"."ai_sandboxes";
create policy ai_sandboxes_read on "better_supabase"."ai_sandboxes" for select to authenticated
  using ("user_id" = (select auth.uid()) or "organization_id" in (select better_supabase.tenant_ids_with('ai_chat.admin')));
do $$
begin
  if exists (
    select 1 from pg_catalog.pg_attribute
    where attrelid = '"better_supabase"."ai_harness_sessions"'::regclass and attname = 'sandbox_id' and not attisdropped
  ) then
    execute $sql$
      insert into "better_supabase"."ai_sandboxes" ("organization_id", "user_id", "chat_id", "harness_id", "provider", "sandbox_id", "status", "last_used_at", "stopped_at", "created_at")
      select c."organization_id", x."owner_id", x."chat_id", x."harness_id", 'harness', x.sandbox_id,
        case when x."status" = 'stopped' then 'stopped' else 'running' end,
        x."last_active_at",
        case when x."status" = 'stopped' then x."updated_at" end,
        x."created_at"
      from "better_supabase"."ai_harness_sessions" x
      join "better_supabase"."ai_chats" c on c."id" = x."chat_id"
      where x.sandbox_id is not null and length(x.sandbox_id) between 1 and 200
      on conflict ("provider", "sandbox_id") do nothing
    $sql$;
    alter table "better_supabase"."ai_harness_sessions" drop column sandbox_id;
  end if;
end;
$$;

-- memory: version 1 to 2. Memories gain a project scope: a project_id column, the scope check allows 'project', and the path index covers the project.
alter table "better_supabase"."memories" add column if not exists "project_id" uuid references "better_supabase"."ai_projects" ("id") on delete cascade;
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."memories"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'scope'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."memories"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."memories" add constraint "memories_scope_check" check ("scope" in ('user', 'agent', 'chat', 'project', 'organization'));
-- The module file creates the path index again with the project column.
do $$
declare
  v_index regclass;
begin
  select i.indexrelid::regclass into v_index
  from pg_catalog.pg_index i
  join pg_catalog.pg_class c on c.oid = i.indexrelid
  where i.indrelid = '"better_supabase"."memories"'::regclass and c.relname = 'memories_path_idx';
  if v_index is not null then
    execute format('drop index %s', v_index);
  end if;
end;
$$;

-- ai-tasks: version 1 to 2. Task runs end completed instead of succeeded.
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."ai_task_runs"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'status'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_task_runs"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."ai_task_runs" add constraint "ai_task_runs_status_check" check ("status" in ('queued', 'running', 'completed', 'failed', 'succeeded'));
update "better_supabase"."ai_task_runs" set "status" = 'completed' where "status" = 'succeeded';
do $$
declare
  v_name name;
begin
  for v_name in
    select c.conname from pg_catalog.pg_constraint c
    join pg_catalog.pg_attribute a on a.attrelid = c.conrelid and a.attnum = c.conkey[1]
    where c.conrelid = '"better_supabase"."ai_task_runs"'::regclass and c.contype = 'c'
      and cardinality(c.conkey) = 1 and a.attname = 'status'
  loop
    execute format('alter table %s drop constraint %I', '"better_supabase"."ai_task_runs"', v_name);
  end loop;
end;
$$;
alter table "better_supabase"."ai_task_runs" add constraint "ai_task_runs_status_check" check ("status" in ('queued', 'running', 'completed', 'failed'));
