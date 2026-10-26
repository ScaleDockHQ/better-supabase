-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:388ab7e0efd21c4a4f1bbbe0835f32eebe8910182d13f17e96af9c12537aa8f7
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

create or replace function better_supabase.actor_may_write()
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select case
    when auth.jwt() is null then true
    when auth.jwt() -> 'act' ->> 'kind' = 'support'
      then coalesce(auth.jwt() -> 'act' -> 'read_only' = 'false'::jsonb, false)
    when auth.jwt() -> 'act' ->> 'kind' = 'agent'
      then coalesce(auth.jwt() -> 'act' -> 'read_only', 'false'::jsonb) = 'false'::jsonb
    when auth.jwt() -> 'act' ->> 'kind' is not null then false
    when auth.jwt() -> 'act' ->> 'session_id' is not null
      and auth.jwt() -> 'act' ->> 'kind' is null then false
    else true
  end
$$;
revoke execute on function better_supabase.actor_may_write() from public;
grant execute on function better_supabase.actor_may_write() to anon, authenticated, service_role;

create or replace function better_supabase.raise_actor_readonly()
returns void
language plpgsql
volatile
set search_path = ''
as $$
begin
  raise exception 'This session is read-only' using errcode = '42501', hint = 'ACTOR_READ_ONLY';
end;
$$;
revoke execute on function better_supabase.raise_actor_readonly() from public;
grant execute on function better_supabase.raise_actor_readonly() to anon, authenticated, service_role;

create table if not exists "public"."projects" (
  id uuid primary key default gen_random_uuid(),
  "user_id" uuid default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "user_id" uuid default auth.uid() references auth.users (id) on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."projects" add column if not exists "name" text not null;
alter table "public"."projects" add column if not exists "budget_minor" bigint not null default 0;
alter table "public"."projects" add column if not exists "currency" text not null default 'EUR';
alter table "public"."projects" add column if not exists "owner_id" uuid references auth.users (id) on delete set null;

alter table "public"."tasks" add column if not exists "project_id" uuid not null references "public"."projects" (id) on delete cascade;
alter table "public"."tasks" add column if not exists "title" text not null;
alter table "public"."tasks" add column if not exists "done" boolean not null default false;
alter table "public"."tasks" add column if not exists "labels" text[] default '{}';

alter table "public"."projects" enable row level security;
revoke all on "public"."projects" from public, anon, authenticated;
grant select, insert, update, delete on "public"."projects" to authenticated;
grant all on "public"."projects" to service_role;
drop policy if exists projects_select on "public"."projects";
create policy projects_select on "public"."projects"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists projects_insert on "public"."projects";
create policy projects_insert on "public"."projects"
  for insert to authenticated
  with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists projects_update on "public"."projects";
create policy projects_update on "public"."projects"
  for update to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists projects_delete on "public"."projects";
create policy projects_delete on "public"."projects"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
create index if not exists "projects_user_id_idx" on "public"."projects" ("user_id");
create index if not exists "projects_owner_id_idx" on "public"."projects" ("owner_id");
drop trigger if exists "bsb_updated_at" on "public"."projects";
create trigger "bsb_updated_at" before update on "public"."projects"
  for each row execute function better_supabase.set_updated_at();

alter table "public"."tasks" enable row level security;
revoke all on "public"."tasks" from public, anon, authenticated;
grant select, insert, update, delete on "public"."tasks" to authenticated;
grant all on "public"."tasks" to service_role;
drop policy if exists tasks_select on "public"."tasks";
create policy tasks_select on "public"."tasks"
  for select to authenticated
  using ("user_id" = (select auth.uid()));
drop policy if exists tasks_insert on "public"."tasks";
create policy tasks_insert on "public"."tasks"
  for insert to authenticated
  with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists tasks_update on "public"."tasks";
create policy tasks_update on "public"."tasks"
  for update to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()))
  with check (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
drop policy if exists tasks_delete on "public"."tasks";
create policy tasks_delete on "public"."tasks"
  for delete to authenticated
  using (("user_id" = (select auth.uid())) and (select better_supabase.actor_may_write()));
create index if not exists "tasks_user_id_idx" on "public"."tasks" ("user_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
drop trigger if exists "bsb_updated_at" on "public"."tasks";
create trigger "bsb_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:c04eea844da8a9543240a4021f8abc16feee69a21b043a2ea5ae3c6fdaf51c8c
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(14);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.projects');

with u as (
  insert into auth.users (id, email, aud, role, instance_id)
  values (gen_random_uuid(), 'bsb-app-tables-' || gen_random_uuid()::text || '@example.test', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  returning id
)
insert into "public"."projects" ("user_id", "name") select u.id, repeat('x', 1) from u;

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."projects"), 0, 'a signed-in user does not read a row of public.projects outside their scope');
select extensions.throws_ok($$insert into "public"."projects" ("user_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.projects outside their scope');
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete'], 'public.tasks has the policies for its scope');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.tasks has a required reference, so the read test can''t insert a row of another user', 1);
select extensions.throws_ok($$insert into "public"."tasks" ("user_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope');
reset role;

select * from extensions.finish();
rollback;
