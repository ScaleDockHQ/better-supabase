-- better-supabase module: app-tables (0.9.0)
-- @bs-app-tables
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase sql sync`; re-running it overwrites this file.
-- Change it through `appTables` in better-supabase.config.ts.

create table if not exists "public"."projects" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "public"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."saved_views" (
  id uuid primary key default gen_random_uuid(),
  "user_id" uuid default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."projects" add column if not exists "name" text not null;
alter table "public"."projects" add column if not exists "budget_minor" bigint not null default 0;
alter table "public"."projects" add column if not exists "currency" text not null default 'EUR';
alter table "public"."projects" add column if not exists "lead_id" uuid references auth.users (id) on delete set null;
alter table "public"."projects" add column if not exists "label_id" uuid references "better_supabase"."tags" ("id") on delete set null;
alter table "public"."projects" add column if not exists "internal_notes" text;
alter table "public"."projects" add column if not exists "deleted_at" timestamptz;

alter table "public"."tasks" add column if not exists "title" text not null;
alter table "public"."tasks" add column if not exists "status" text not null default 'todo';
alter table "public"."tasks" add column if not exists "starts_on" date;
alter table "public"."tasks" add column if not exists "due_on" date;
alter table "public"."tasks" add column if not exists "assignee_id" uuid references auth.users (id) on delete set null;
alter table "public"."tasks" add column if not exists "project_id" uuid not null;
alter table "public"."tasks" add column if not exists "rank" text collate "C" not null default 'V';

alter table "public"."saved_views" add column if not exists "name" text not null;
alter table "public"."saved_views" add column if not exists "filters" jsonb not null default '{}';

alter table "public"."projects" enable row level security;
revoke all on "public"."projects" from anon, authenticated;
grant select ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at") on "public"."projects" to authenticated;
grant insert ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at"), update ("id", "organization_id", "created_at", "updated_at", "name", "budget_minor", "currency", "lead_id", "label_id", "deleted_at") on "public"."projects" to authenticated;
grant delete on "public"."projects" to authenticated;
grant all on "public"."projects" to service_role;
drop policy if exists "projects_select" on "public"."projects";
create policy "projects_select" on "public"."projects" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "projects_insert" on "public"."projects";
create policy "projects_insert" on "public"."projects" for insert to authenticated with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "projects_update" on "public"."projects";
create policy "projects_update" on "public"."projects" for update to authenticated using ("organization_id" in (select better_supabase.member_organization_ids())) with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "projects_delete" on "public"."projects";
create policy "projects_delete" on "public"."projects" for delete to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
create index if not exists "projects_organization_id_idx" on "public"."projects" ("organization_id");
create index if not exists "projects_lead_id_idx" on "public"."projects" ("lead_id");
create index if not exists "projects_label_id_idx" on "public"."projects" ("label_id");
drop trigger if exists "bs_updated_at" on "public"."projects";
create trigger "bs_updated_at" before update on "public"."projects"
  for each row execute function better_supabase.set_updated_at();

alter table "public"."tasks" enable row level security;
revoke all on "public"."tasks" from anon, authenticated;
grant select, insert, update, delete on "public"."tasks" to authenticated;
grant all on "public"."tasks" to service_role;
drop policy if exists "tasks_select" on "public"."tasks";
create policy "tasks_select" on "public"."tasks" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "tasks_insert" on "public"."tasks";
create policy "tasks_insert" on "public"."tasks" for insert to authenticated with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "tasks_update" on "public"."tasks";
create policy "tasks_update" on "public"."tasks" for update to authenticated using ("organization_id" in (select better_supabase.member_organization_ids())) with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "tasks_delete" on "public"."tasks";
create policy "tasks_delete" on "public"."tasks" for delete to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
alter table "public"."tasks" drop constraint if exists "tasks_title_check";
alter table "public"."tasks" add constraint "tasks_title_check" check (char_length("title") <= 200);
alter table "public"."tasks" drop constraint if exists "tasks_status_check";
alter table "public"."tasks" add constraint "tasks_status_check" check ("status" in ('todo', 'doing', 'done'));
alter table "public"."tasks" drop constraint if exists "tasks_project_id_title_key";
alter table "public"."tasks" add constraint "tasks_project_id_title_key" unique ("project_id", "title");
create index if not exists "tasks_organization_id_idx" on "public"."tasks" ("organization_id");
create index if not exists "tasks_assignee_id_idx" on "public"."tasks" ("assignee_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
create index if not exists "tasks_status_rank_idx" on "public"."tasks" ("status", "rank");
drop trigger if exists "bs_updated_at" on "public"."tasks";
create trigger "bs_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();
create or replace function "better_supabase"."tasks_emit_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_changed text[];
begin
  if tg_op = 'INSERT' then
    v_row := to_jsonb(new);
    perform "better_supabase".emit_event('task.created', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  if tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    select coalesce(array_agg(n.key order by n.key), array[]::text[]) into v_changed
      from jsonb_each(v_row) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if cardinality(v_changed) > 0 then
      perform "better_supabase".emit_event('task.updated', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id', 'changed', to_jsonb(v_changed)), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
    end if;
  end if;
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    perform "better_supabase".emit_event('task.deleted', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'project_id', v_row -> 'project_id'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  return null;
end;
$$;
revoke all on function "better_supabase"."tasks_emit_event"() from public, anon, authenticated;
drop trigger if exists "bs_emit_event" on "public"."tasks";
create trigger "bs_emit_event" after insert or update or delete on "public"."tasks"
  for each row execute function "better_supabase"."tasks_emit_event"();

alter table "public"."saved_views" enable row level security;
revoke all on "public"."saved_views" from anon, authenticated;
grant select, insert, update, delete on "public"."saved_views" to authenticated;
grant all on "public"."saved_views" to service_role;
drop policy if exists "saved_views_select" on "public"."saved_views";
create policy "saved_views_select" on "public"."saved_views" for select to authenticated using ("user_id" = (select auth.uid()));
drop policy if exists "saved_views_insert" on "public"."saved_views";
create policy "saved_views_insert" on "public"."saved_views" for insert to authenticated with check ("user_id" = (select auth.uid()));
drop policy if exists "saved_views_update" on "public"."saved_views";
create policy "saved_views_update" on "public"."saved_views" for update to authenticated using ("user_id" = (select auth.uid())) with check ("user_id" = (select auth.uid()));
drop policy if exists "saved_views_delete" on "public"."saved_views";
create policy "saved_views_delete" on "public"."saved_views" for delete to authenticated using ("user_id" = (select auth.uid()));
create index if not exists "saved_views_user_id_idx" on "public"."saved_views" ("user_id");
drop trigger if exists "bs_updated_at" on "public"."saved_views";
create trigger "bs_updated_at" before update on "public"."saved_views"
  for each row execute function better_supabase.set_updated_at();

create unique index if not exists "projects_organization_id_id_key" on "public"."projects" ("organization_id", id);
alter table "public"."tasks" drop constraint if exists "tasks_project_id_fkey";
alter table "public"."tasks" add constraint "tasks_project_id_fkey" foreign key ("organization_id", "project_id") references "public"."projects" ("organization_id", id) on delete cascade;

drop view if exists "public"."projects_view";
create view "public"."projects_view" with (security_invoker = true) as
select t."id",
  t."organization_id",
  t."created_at",
  t."updated_at",
  t."name",
  t."budget_minor",
  t."currency",
  t."lead_id",
  t."label_id",
  t."deleted_at",
  r0.value as "open_tasks",
  r1.value as "done_tasks",
  r2.value as "next_due_on"
from "public"."projects" t
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'todo') r0 on true
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'done') r1 on true
  left join lateral (select min(c."due_on") as value from "public"."tasks" c where c."project_id" = t.id) r2 on true;
revoke all on "public"."projects_view" from anon, authenticated;
grant select on "public"."projects_view" to authenticated;
grant select on "public"."projects_view" to service_role;
comment on view "public"."projects_view" is 'The rollups and lookups of public.projects, read with the caller''s row level security.';

drop view if exists "public"."tasks_view";
create view "public"."tasks_view" with (security_invoker = true) as
select t.*,
  l0.value as "project_name"
from "public"."tasks" t
  left join lateral (select r."name" as value from "public"."projects" r where r.id = t."project_id") l0 on true;
revoke all on "public"."tasks_view" from anon, authenticated;
grant select on "public"."tasks_view" to authenticated;
grant select on "public"."tasks_view" to service_role;
comment on view "public"."tasks_view" is 'The rollups and lookups of public.tasks, read with the caller''s row level security.';

drop trigger if exists "bs_search_project_index" on "public"."projects";
create trigger "bs_search_project_index"
  after insert or delete or update of "id", "organization_id", "name", "deleted_at" on "public"."projects"
  for each row execute function "better_supabase"."search_index_row"('project', 'id');

-- Sets columns of one app table row for the bulk action appTables.set. It runs
-- as the caller, so the table's policies and grants decide what changes.
create or replace function public."app_table_set"(tenant uuid, subject_type text, subject_id text, args jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_values jsonb := coalesce(app_table_set.args -> 'values', '{}'::jsonb);
  v_count integer := 0;
begin
  if jsonb_typeof(v_values) <> 'object' or v_values = '{}'::jsonb then
    raise exception 'pass the columns to set as args.values' using errcode = '22023', hint = 'APP_TABLE_SET_EMPTY';
  end if;
  case app_table_set.subject_type
    when 'project' then
      if exists (select 1 from jsonb_object_keys(v_values) k where not (k = any ('{name,budget_minor,currency,lead_id,label_id}'::text[]))) then
        raise exception 'only these columns of projects can be set: name, budget_minor, currency, lead_id, label_id' using errcode = '22023', hint = 'APP_TABLE_SET_COLUMN';
      end if;
      update public."projects" t set
          "name" = case when v_values ? 'name' then r."name" else t."name" end,
          "budget_minor" = case when v_values ? 'budget_minor' then r."budget_minor" else t."budget_minor" end,
          "currency" = case when v_values ? 'currency' then r."currency" else t."currency" end,
          "lead_id" = case when v_values ? 'lead_id' then r."lead_id" else t."lead_id" end,
          "label_id" = case when v_values ? 'label_id' then r."label_id" else t."label_id" end
        from jsonb_populate_record(null::public."projects", v_values) r
        where t.id = app_table_set.subject_id::uuid
        and t."organization_id" = app_table_set.tenant;
      get diagnostics v_count = row_count;
    when 'task' then
      if exists (select 1 from jsonb_object_keys(v_values) k where not (k = any ('{title,status,starts_on,due_on,assignee_id,project_id}'::text[]))) then
        raise exception 'only these columns of tasks can be set: title, status, starts_on, due_on, assignee_id, project_id' using errcode = '22023', hint = 'APP_TABLE_SET_COLUMN';
      end if;
      update public."tasks" t set
          "title" = case when v_values ? 'title' then r."title" else t."title" end,
          "status" = case when v_values ? 'status' then r."status" else t."status" end,
          "starts_on" = case when v_values ? 'starts_on' then r."starts_on" else t."starts_on" end,
          "due_on" = case when v_values ? 'due_on' then r."due_on" else t."due_on" end,
          "assignee_id" = case when v_values ? 'assignee_id' then r."assignee_id" else t."assignee_id" end,
          "project_id" = case when v_values ? 'project_id' then r."project_id" else t."project_id" end
        from jsonb_populate_record(null::public."tasks", v_values) r
        where t.id = app_table_set.subject_id::uuid
        and t."organization_id" = app_table_set.tenant;
      get diagnostics v_count = row_count;
    else
      raise exception 'not an app table subject type' using errcode = '22023', hint = 'APP_TABLE_SET_SUBJECT';
  end case;
  if v_count = 0 then
    raise exception 'row not found or not writable' using errcode = 'P0002', hint = 'APP_TABLE_SET_NOT_FOUND';
  end if;
end;
$$;
revoke execute on function public."app_table_set"(uuid, text, text, jsonb) from public, anon;
grant execute on function public."app_table_set"(uuid, text, text, jsonb) to authenticated, service_role;
