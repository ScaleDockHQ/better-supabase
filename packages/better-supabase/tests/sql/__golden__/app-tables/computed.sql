-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:b67b2669e51c8d53a36283a1eec2131dba4f497825fb1751e22febebe48d8f6a
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

alter table "public"."projects" add column if not exists "name" text not null;

alter table "public"."tasks" add column if not exists "project_id" uuid not null;
alter table "public"."tasks" add column if not exists "status" text;
alter table "public"."tasks" add column if not exists "estimate" integer;
alter table "public"."tasks" add column if not exists "due_on" date;

alter table "public"."projects" enable row level security;
revoke all on "public"."projects" from anon, authenticated;
grant select, insert, update, delete on "public"."projects" to authenticated;
grant all on "public"."projects" to service_role;
drop policy if exists "projects_select" on "public"."projects";
create policy "projects_select" on "public"."projects" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "projects_insert" on "public"."projects";
create policy "projects_insert" on "public"."projects" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "projects_update" on "public"."projects";
create policy "projects_update" on "public"."projects" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "projects_delete" on "public"."projects";
create policy "projects_delete" on "public"."projects" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_tenant_scope on "public"."projects";
drop policy if exists bsb_tenant_scope_select on "public"."projects";
create policy bsb_tenant_scope_select on "public"."projects" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "public"."projects";
create policy bsb_tenant_scope_insert on "public"."projects" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "public"."projects";
create policy bsb_tenant_scope_update on "public"."projects" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "public"."projects";
create policy bsb_tenant_scope_delete on "public"."projects" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
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
create policy "tasks_insert" on "public"."tasks" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "tasks_update" on "public"."tasks";
create policy "tasks_update" on "public"."tasks" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "tasks_delete" on "public"."tasks";
create policy "tasks_delete" on "public"."tasks" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_tenant_scope on "public"."tasks";
drop policy if exists bsb_tenant_scope_select on "public"."tasks";
create policy bsb_tenant_scope_select on "public"."tasks" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "public"."tasks";
create policy bsb_tenant_scope_insert on "public"."tasks" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "public"."tasks";
create policy bsb_tenant_scope_update on "public"."tasks" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "public"."tasks";
create policy bsb_tenant_scope_delete on "public"."tasks" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
alter table "public"."tasks" drop constraint if exists "tasks_status_check";
alter table "public"."tasks" add constraint "tasks_status_check" check ("status" in ('todo', 'done'));
create index if not exists "tasks_organization_id_idx" on "public"."tasks" ("organization_id");
create index if not exists "tasks_project_id_idx" on "public"."tasks" ("project_id");
drop trigger if exists "bsb_updated_at" on "public"."tasks";
create trigger "bsb_updated_at" before update on "public"."tasks"
  for each row execute function better_supabase.set_updated_at();

create unique index if not exists "projects_organization_id_id_key" on "public"."projects" ("organization_id", id);
alter table "public"."tasks" drop constraint if exists "tasks_project_id_fkey";
alter table "public"."tasks" add constraint "tasks_project_id_fkey" foreign key ("organization_id", "project_id") references "public"."projects" ("organization_id", id) on delete cascade;

drop view if exists "public"."projects_view";
create view "public"."projects_view" with (security_invoker = true) as
select t.*,
  r0.value as "done_tasks",
  r1.value as "estimate_total",
  r2.value as "last_due"
from "public"."projects" t
  left join lateral (select count(*) as value from "public"."tasks" c where c."project_id" = t.id and c."status" = 'done') r0 on true
  left join lateral (select coalesce(sum(c."estimate"), 0) as value from "public"."tasks" c where c."project_id" = t.id) r1 on true
  left join lateral (select max(c."due_on") as value from "public"."tasks" c where c."project_id" = t.id) r2 on true;
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

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:d84e2c43b6adbff2e53462a2b30b2ee85f48647906434d4b6490b1425c6e2fa0
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(26);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.projects');
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
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.tasks has the policies for its scope');
select extensions.col_has_check('public'::name, 'tasks'::name, 'status'::name, 'public.tasks.status has its check');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."tasks"'::regclass and k.conname = 'tasks_project_id_fkey' and k.contype = 'f' and cardinality(k.conkey) = 2), 'public.tasks.project_id references a row of the same tenant');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');
select extensions.has_view('public', 'tasks_view', 'public.tasks_view exists');
select extensions.ok((select coalesce('security_invoker=true' = any(c.reloptions), false) from pg_catalog.pg_class c where c.oid = '"public"."tasks_view"'::regclass), 'public.tasks_view runs with the caller''s row level security');
select extensions.table_privs_are('public', 'tasks_view', 'anon', array[]::text[], 'anon has no privileges on public.tasks_view');
select extensions.table_privs_are('public', 'tasks_view', 'authenticated', array['SELECT'], 'authenticated only reads public.tasks_view');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."tasks" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.tasks has a required reference, so the read test can''t insert a row of another tenant', 1);
select extensions.throws_ok($$insert into "public"."tasks" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope even through an app policy using (true)');
select extensions.is((select count(*)::integer from "public"."tasks_view"), 0, 'a stranger sees no rows of public.tasks_view');
reset role;

select * from extensions.finish();
rollback;
