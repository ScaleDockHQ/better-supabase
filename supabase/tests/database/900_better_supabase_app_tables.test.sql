-- better-supabase module: app-tables (0.8.0)
-- @bs-module-test app-tables
-- Managed by `better-supabase sql sync`; re-running it overwrites this file.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(24);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete', 'bs_session_active'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.projects');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."projects" where not ("organization_id" in (select better_supabase.member_organization_ids()))), 0, 'a signed-in user reads only the rows of public.projects their scope reaches');
select extensions.throws_ok($$insert into "public"."projects" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.projects outside their scope');
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete', 'bs_session_active'], 'public.tasks has the policies for its scope');
select extensions.col_has_check('public'::name, 'tasks'::name, 'title'::name, 'public.tasks.title has its check');
select extensions.col_has_check('public'::name, 'tasks'::name, 'status'::name, 'public.tasks.status has its check');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."tasks"'::regclass and k.conname = 'tasks_project_id_fkey' and k.contype = 'f' and cardinality(k.conkey) = 2), 'public.tasks.project_id references a row of the same tenant');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."tasks" where not ("organization_id" in (select better_supabase.member_organization_ids()))), 0, 'a signed-in user reads only the rows of public.tasks their scope reaches');
select extensions.throws_ok($$insert into "public"."tasks" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope');
reset role;

select extensions.has_table('public', 'saved_views', 'public.saved_views exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."saved_views"'::regclass), 'public.saved_views has row level security on');
select extensions.policies_are('public', 'saved_views', array['saved_views_select', 'saved_views_insert', 'saved_views_update', 'saved_views_delete', 'bs_session_active'], 'public.saved_views has the policies for its scope');
select extensions.table_privs_are('public', 'saved_views', 'anon', array[]::text[], 'anon has no privileges on public.saved_views');
select extensions.table_privs_are('public', 'saved_views', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.saved_views');

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."saved_views" where not ("user_id" = (select auth.uid()))), 0, 'a signed-in user reads only the rows of public.saved_views their scope reaches');
select extensions.throws_ok($$insert into "public"."saved_views" ("user_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.saved_views outside their scope');
reset role;

select * from extensions.finish();
rollback;
