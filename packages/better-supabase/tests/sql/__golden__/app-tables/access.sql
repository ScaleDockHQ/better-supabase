-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase upgrade`; re-running it overwrites this file.
-- Change it through `appTables` in better-supabase.config.ts.

create table if not exists "public"."projects" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "better_supabase"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "better_supabase"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."rates" (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."projects" add column if not exists "name" text not null;
alter table "public"."projects" add column if not exists "budget" numeric;
alter table "public"."projects" add column if not exists "internal_notes" text;

alter table "public"."tasks" add column if not exists "project_id" uuid not null;

alter table "public"."rates" add column if not exists "cost" numeric;

alter table "public"."projects" enable row level security;
revoke all on "public"."projects" from anon, authenticated;
grant select ("id", "organization_id", "created_at", "updated_at", "name", "budget") on "public"."projects" to authenticated;
grant insert ("id", "organization_id", "created_at", "updated_at", "name"), update ("id", "organization_id", "created_at", "updated_at", "name") on "public"."projects" to authenticated;
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
drop policy if exists bsb_tenant_scope on "public"."projects";
create policy bsb_tenant_scope on "public"."projects" as restrictive
  for all to authenticated
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create index if not exists "projects_organization_id_idx" on "public"."projects" ("organization_id");
drop trigger if exists "bsb_updated_at" on "public"."projects";
create trigger "bsb_updated_at" before update on "public"."projects"
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
drop policy if exists bsb_tenant_scope on "public"."tasks";
create policy bsb_tenant_scope on "public"."tasks" as restrictive
  for all to authenticated
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create index if not exists "tasks_organization_id_idx" on "public"."tasks" ("organization_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
drop trigger if exists "bsb_updated_at" on "public"."tasks";
create trigger "bsb_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

alter table "public"."rates" enable row level security;
revoke all on "public"."rates" from anon, authenticated;
grant select ("id", "created_at", "updated_at") on "public"."rates" to authenticated;
grant all on "public"."rates" to service_role;
drop policy if exists "rates_select" on "public"."rates";
create policy "rates_select" on "public"."rates" for select to authenticated using (((select auth.uid()) is not null));
drop trigger if exists "bsb_updated_at" on "public"."rates";
create trigger "bsb_updated_at" before update on "public"."rates"
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
  t."budget",
  r0.value as "open_tasks"
from "public"."projects" t
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id) r0 on true;
revoke all on "public"."projects_view" from anon, authenticated;
grant select on "public"."projects_view" to authenticated;
grant select on "public"."projects_view" to service_role;
comment on view "public"."projects_view" is 'The rollups and lookups of public.projects, read with the caller''s row level security.';

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- Managed by `better-supabase upgrade`; re-running it overwrites this file.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(39);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete', 'bsb_tenant_scope'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE'], 'authenticated has the privileges for its scope on public.projects');
select extensions.ok(has_column_privilege('authenticated', '"public"."projects"', 'budget', 'SELECT'), 'authenticated may select public.projects.budget');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'budget', 'INSERT'), 'authenticated may not insert public.projects.budget');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'budget', 'UPDATE'), 'authenticated may not update public.projects.budget');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'SELECT'), 'authenticated may not select public.projects.internal_notes');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'INSERT'), 'authenticated may not insert public.projects.internal_notes');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'UPDATE'), 'authenticated may not update public.projects.internal_notes');
select extensions.has_view('public', 'projects_view', 'public.projects_view exists');
select extensions.ok((select coalesce('security_invoker=true' = any(c.reloptions), false) from pg_catalog.pg_class c where c.oid = '"public"."projects_view"'::regclass), 'public.projects_view runs with the caller''s row level security');
select extensions.table_privs_are('public', 'projects_view', 'anon', array[]::text[], 'anon has no privileges on public.projects_view');
select extensions.table_privs_are('public', 'projects_view', 'authenticated', array['SELECT'], 'authenticated only reads public.projects_view');

with o as (
  insert into "better_supabase"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."projects" ("organization_id", "name") select o.id, repeat('x', 1) from o;

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."projects" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."projects"), 0, 'a signed-in user does not read a row of public.projects outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."projects" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.projects outside their scope even through an app policy using (true)');
select extensions.is((select count(*)::integer from "public"."projects_view"), 0, 'a stranger sees no rows of public.projects_view');
select extensions.throws_ok($$select "internal_notes" from "public"."projects"$$, '42501', null, 'a signed-in user cannot read public.projects.internal_notes');
select extensions.throws_ok($$update "public"."projects" set "budget" = null where false$$, '42501', null, 'a signed-in user cannot write public.projects.budget');
select extensions.throws_ok($$update "public"."projects" set "internal_notes" = null where false$$, '42501', null, 'a signed-in user cannot write public.projects.internal_notes');
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete', 'bsb_tenant_scope'], 'public.tasks has the policies for its scope');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."tasks"'::regclass and k.conname = 'tasks_project_id_fkey' and k.contype = 'f' and cardinality(k.conkey) = 2), 'public.tasks.project_id references a row of the same tenant');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."tasks" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.tasks has a required reference, so the read test can''t insert a row of another tenant', 1);
select extensions.throws_ok($$insert into "public"."tasks" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope even through an app policy using (true)');
reset role;

select extensions.has_table('public', 'rates', 'public.rates exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."rates"'::regclass), 'public.rates has row level security on');
select extensions.policies_are('public', 'rates', array['rates_select'], 'public.rates has the policies for its scope');
select extensions.table_privs_are('public', 'rates', 'anon', array[]::text[], 'anon has no privileges on public.rates');
select extensions.table_privs_are('public', 'rates', 'authenticated', array[]::text[], 'authenticated has the privileges for its scope on public.rates');
select extensions.ok(not has_column_privilege('authenticated', '"public"."rates"', 'cost', 'SELECT'), 'authenticated may not select public.rates.cost');
select extensions.ok(not has_column_privilege('authenticated', '"public"."rates"', 'cost', 'INSERT'), 'authenticated may not insert public.rates.cost');
select extensions.ok(not has_column_privilege('authenticated', '"public"."rates"', 'cost', 'UPDATE'), 'authenticated may not update public.rates.cost');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.throws_ok($$insert into "public"."rates" default values$$, '42501', null, 'a signed-in user cannot write public.rates; only the service role does');
select extensions.throws_ok($$select "cost" from "public"."rates"$$, '42501', null, 'a signed-in user cannot read public.rates.cost');
reset role;

select * from extensions.finish();
rollback;
