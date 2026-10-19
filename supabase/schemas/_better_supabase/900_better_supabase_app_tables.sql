-- better-supabase module: app-tables (0.8.0)
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
grant select, insert, update, delete on "public"."projects" to authenticated;
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
create index if not exists "tasks_organization_id_idx" on "public"."tasks" ("organization_id");
create index if not exists "tasks_assignee_id_idx" on "public"."tasks" ("assignee_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
create index if not exists "tasks_status_rank_idx" on "public"."tasks" ("status", "rank");
drop trigger if exists "bs_updated_at" on "public"."tasks";
create trigger "bs_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

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
select t.*,
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
