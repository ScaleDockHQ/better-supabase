-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:ca6916f5e65780af6fd46b3de2a6f4eee28a42d1030af8da886d3ffa54745b16
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

create table if not exists "public"."projects" (
  id uuid primary key default gen_random_uuid(),
  "workspace_id" uuid not null references "better_supabase"."workspaces" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "workspace_id" uuid not null references "better_supabase"."workspaces" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."projects" add column if not exists "name" text not null;
alter table "public"."projects" add column if not exists "budget_minor" bigint not null default 0;
alter table "public"."projects" add column if not exists "currency" text not null default 'EUR';
alter table "public"."projects" add column if not exists "owner_id" uuid references auth.users (id) on delete set null;

alter table "public"."tasks" add column if not exists "project_id" uuid not null;
alter table "public"."tasks" add column if not exists "title" text not null;
alter table "public"."tasks" add column if not exists "done" boolean not null default false;
alter table "public"."tasks" add column if not exists "labels" text[] default '{}';

alter table "public"."projects" enable row level security;
revoke all on "public"."projects" from anon, authenticated;
grant select, insert, update, delete on "public"."projects" to authenticated;
grant all on "public"."projects" to service_role;
drop policy if exists "projects_select" on "public"."projects";
create policy "projects_select" on "public"."projects" for select to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "projects_insert" on "public"."projects";
create policy "projects_insert" on "public"."projects" for insert to authenticated with check ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "projects_update" on "public"."projects";
create policy "projects_update" on "public"."projects" for update to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids())) with check ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "projects_delete" on "public"."projects";
create policy "projects_delete" on "public"."projects" for delete to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids()));
create index if not exists "projects_workspace_id_idx" on "public"."projects" ("workspace_id");
create index if not exists "projects_owner_id_idx" on "public"."projects" ("owner_id");
drop trigger if exists "bsb_updated_at" on "public"."projects";
create trigger "bsb_updated_at" before update on "public"."projects"
  for each row execute function better_supabase.set_updated_at();

alter table "public"."tasks" enable row level security;
revoke all on "public"."tasks" from anon, authenticated;
grant select, insert, update, delete on "public"."tasks" to authenticated;
grant all on "public"."tasks" to service_role;
drop policy if exists "tasks_select" on "public"."tasks";
create policy "tasks_select" on "public"."tasks" for select to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "tasks_insert" on "public"."tasks";
create policy "tasks_insert" on "public"."tasks" for insert to authenticated with check ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "tasks_update" on "public"."tasks";
create policy "tasks_update" on "public"."tasks" for update to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids())) with check ("workspace_id" in (select better_supabase.member_workspace_ids()));
drop policy if exists "tasks_delete" on "public"."tasks";
create policy "tasks_delete" on "public"."tasks" for delete to authenticated using ("workspace_id" in (select better_supabase.member_workspace_ids()));
create index if not exists "tasks_workspace_id_idx" on "public"."tasks" ("workspace_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
drop trigger if exists "bsb_updated_at" on "public"."tasks";
create trigger "bsb_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

create unique index if not exists "projects_workspace_id_id_key" on "public"."projects" ("workspace_id", id);
alter table "public"."tasks" drop constraint if exists "tasks_project_id_fkey";
alter table "public"."tasks" add constraint "tasks_project_id_fkey" foreign key ("workspace_id", "project_id") references "public"."projects" ("workspace_id", id) on delete cascade;

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:4bc9f96ba8e2e6263c2364eb408499a5b622161a765b38bd31c13cd05479c0ec
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(15);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.projects');

with o as (
  insert into "better_supabase"."workspaces" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."projects" ("workspace_id", "name") select o.id, repeat('x', 1) from o;

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."projects"), 0, 'a signed-in user does not read a row of public.projects outside their scope');
select extensions.throws_ok($$insert into "public"."projects" ("workspace_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.projects outside their scope');
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete'], 'public.tasks has the policies for its scope');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."tasks"'::regclass and k.conname = 'tasks_project_id_fkey' and k.contype = 'f' and cardinality(k.conkey) = 2), 'public.tasks.project_id references a row of the same tenant');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.tasks has a required reference, so the read test can''t insert a row of another tenant', 1);
select extensions.throws_ok($$insert into "public"."tasks" ("workspace_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope');
reset role;

select * from extensions.finish();
rollback;
