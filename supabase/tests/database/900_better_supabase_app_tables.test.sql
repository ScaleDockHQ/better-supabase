-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- Managed by `better-supabase upgrade`; re-running it overwrites this file.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(70);

select extensions.has_table('public', 'projects', 'public.projects exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."projects"'::regclass), 'public.projects has row level security on');
select extensions.policies_are('public', 'projects', array['projects_select', 'projects_insert', 'projects_update', 'projects_delete', 'bsb_session_active', 'bsb_tenant_scope'], 'public.projects has the policies for its scope');
select extensions.table_privs_are('public', 'projects', 'anon', array[]::text[], 'anon has no privileges on public.projects');
select extensions.table_privs_are('public', 'projects', 'authenticated', array['DELETE'], 'authenticated has the privileges for its scope on public.projects');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'SELECT'), 'authenticated may not select public.projects.internal_notes');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'INSERT'), 'authenticated may not insert public.projects.internal_notes');
select extensions.ok(not has_column_privilege('authenticated', '"public"."projects"', 'internal_notes', 'UPDATE'), 'authenticated may not update public.projects.internal_notes');
select extensions.has_view('public', 'projects_view', 'public.projects_view exists');
select extensions.ok((select coalesce('security_invoker=true' = any(c.reloptions), false) from pg_catalog.pg_class c where c.oid = '"public"."projects_view"'::regclass), 'public.projects_view runs with the caller''s row level security');
select extensions.table_privs_are('public', 'projects_view', 'anon', array[]::text[], 'anon has no privileges on public.projects_view');
select extensions.table_privs_are('public', 'projects_view', 'authenticated', array['SELECT'], 'authenticated only reads public.projects_view');

with o as (
  insert into "public"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."projects" ("organization_id", "name") select o.id, repeat('x', 1) from o;
select extensions.has_trigger('public'::name, 'projects'::name, 'bsb_versions_project_auto'::name, 'public.projects snapshots a version on each change');
select extensions.ok(exists (select 1 from "better_supabase"."versions" v where v."subject_type" = 'project'), 'an insert into public.projects snapshots a project version');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."projects" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."projects"), 0, 'a signed-in user does not read a row of public.projects outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."projects" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.projects outside their scope even through an app policy using (true)');
select extensions.throws_ok($$select public.app_table_set(gen_random_uuid(), 'project', '1', '{"values": {"id": "1"}}'::jsonb)$$, '22023', null, 'appTables.set refuses the id of public.projects');
select extensions.throws_ok($$select public.app_table_set(gen_random_uuid(), 'project', '1', '{"values": {}}'::jsonb)$$, '22023', null, 'appTables.set on public.projects needs values');
select extensions.is((select count(*)::integer from "public"."projects_view"), 0, 'a stranger sees no rows of public.projects_view');
select extensions.throws_ok($$select "internal_notes" from "public"."projects"$$, '42501', null, 'a signed-in user cannot read public.projects.internal_notes');
select extensions.throws_ok($$update "public"."projects" set "internal_notes" = null where false$$, '42501', null, 'a signed-in user cannot write public.projects.internal_notes');
reset role;

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete', 'bsb_session_active', 'bsb_tenant_scope'], 'public.tasks has the policies for its scope');
select extensions.col_has_check('public'::name, 'tasks'::name, 'title'::name, 'public.tasks.title has its check');
select extensions.col_has_check('public'::name, 'tasks'::name, 'status'::name, 'public.tasks.status has its check');
select extensions.col_is_unique('public'::name, 'tasks'::name, array['project_id', 'title']::name[], 'public.tasks is unique on project_id, title');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."tasks"'::regclass and k.conname = 'tasks_project_id_fkey' and k.contype = 'f' and cardinality(k.conkey) = 2), 'public.tasks.project_id references a row of the same tenant');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');
select extensions.has_view('public', 'tasks_view', 'public.tasks_view exists');
select extensions.ok((select coalesce('security_invoker=true' = any(c.reloptions), false) from pg_catalog.pg_class c where c.oid = '"public"."tasks_view"'::regclass), 'public.tasks_view runs with the caller''s row level security');
select extensions.table_privs_are('public', 'tasks_view', 'anon', array[]::text[], 'anon has no privileges on public.tasks_view');
select extensions.table_privs_are('public', 'tasks_view', 'authenticated', array['SELECT'], 'authenticated only reads public.tasks_view');
select extensions.has_trigger('public'::name, 'tasks'::name, 'bsb_emit_event'::name, 'public.tasks emits outbox events');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."tasks" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.tasks has a required reference, so the read test can''t insert a row of another tenant', 1);
select extensions.throws_ok($$insert into "public"."tasks" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope even through an app policy using (true)');
select extensions.throws_ok($$select public.app_table_set(gen_random_uuid(), 'task', '1', '{"values": {"id": "1"}}'::jsonb)$$, '22023', null, 'appTables.set refuses the id of public.tasks');
select extensions.throws_ok($$select public.app_table_set(gen_random_uuid(), 'task', '1', '{"values": {}}'::jsonb)$$, '22023', null, 'appTables.set on public.tasks needs values');
select extensions.is((select count(*)::integer from "public"."tasks_view"), 0, 'a stranger sees no rows of public.tasks_view');
reset role;

select extensions.has_table('public', 'client_notes', 'public.client_notes exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."client_notes"'::regclass), 'public.client_notes has row level security on');
select extensions.policies_are('public', 'client_notes', array['client_notes_select', 'client_notes_insert', 'client_notes_update', 'client_notes_delete', 'bsb_session_active', 'bsb_tenant_scope'], 'public.client_notes has the policies for its scope');
select extensions.table_privs_are('public', 'client_notes', 'anon', array[]::text[], 'anon has no privileges on public.client_notes');
select extensions.table_privs_are('public', 'client_notes', 'authenticated', array['DELETE'], 'authenticated has the privileges for its scope on public.client_notes');
select extensions.ok(not has_column_privilege('authenticated', '"public"."client_notes"', 'diagnosis', 'SELECT'), 'authenticated may not select public.client_notes.diagnosis');
select extensions.ok(has_column_privilege('authenticated', '"public"."client_notes"', 'diagnosis', 'INSERT'), 'authenticated may insert public.client_notes.diagnosis');
select extensions.ok(has_column_privilege('authenticated', '"public"."client_notes"', 'diagnosis', 'UPDATE'), 'authenticated may update public.client_notes.diagnosis');
select extensions.ok(not has_column_privilege('authenticated', '"public"."client_notes"', 'birth_date', 'SELECT'), 'authenticated may not select public.client_notes.birth_date');
select extensions.ok(has_column_privilege('authenticated', '"public"."client_notes"', 'birth_date', 'INSERT'), 'authenticated may insert public.client_notes.birth_date');
select extensions.ok(has_column_privilege('authenticated', '"public"."client_notes"', 'birth_date', 'UPDATE'), 'authenticated may update public.client_notes.birth_date');
select extensions.has_trigger('public'::name, 'client_notes'::name, 'bsb_seal_fields'::name, 'public.client_notes encrypts its encrypted columns');
select extensions.has_function('public'::name, 'client_notes_reveal'::name, array['uuid[]']::name[], 'public.client_notes has a reveal function');
select extensions.ok(not has_function_privilege('anon', '"public"."client_notes_reveal"(uuid[])', 'execute'), 'anon cannot reveal public.client_notes');

with o as (
  insert into "public"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."client_notes" ("organization_id", "client_name") select o.id, repeat('x', 1) from o;
update "public"."client_notes" set "diagnosis" = (repeat('x', 1))::text, "birth_date" = ('2026-01-01'::date)::text;
select set_config('bsb.app_reveal_ids', (select array_agg(id)::text from "public"."client_notes"), true);
select set_config('request.jwt.claims', json_build_object('role', 'service_role')::text, true);
select extensions.ok((select bool_and(left("diagnosis", 5) = 'bsf1:' and "diagnosis" <> (repeat('x', 1))::text) from "public"."client_notes"), 'public.client_notes.diagnosis is ciphertext at rest');
select extensions.is((select r."diagnosis"::text from "public"."client_notes_reveal"(current_setting('bsb.app_reveal_ids')::uuid[]) r limit 1), (repeat('x', 1))::text, 'the service role reveals public.client_notes.diagnosis');
select extensions.ok((select bool_and(left("birth_date", 5) = 'bsf1:' and "birth_date" <> ('2026-01-01'::date)::text) from "public"."client_notes"), 'public.client_notes.birth_date is ciphertext at rest');
select extensions.is((select r."birth_date"::text from "public"."client_notes_reveal"(current_setting('bsb.app_reveal_ids')::uuid[]) r limit 1), ('2026-01-01'::date)::text, 'the service role reveals public.client_notes.birth_date');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."client_notes" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."client_notes"), 0, 'a signed-in user does not read a row of public.client_notes outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."client_notes" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.client_notes outside their scope even through an app policy using (true)');
select extensions.is((select count(*)::integer from "public"."client_notes_reveal"(current_setting('bsb.app_reveal_ids')::uuid[])), 0, 'a signed-in user does not reveal a row of public.client_notes outside their scope');
select extensions.throws_ok($$select "diagnosis" from "public"."client_notes"$$, '42501', null, 'a signed-in user cannot read public.client_notes.diagnosis');
select extensions.throws_ok($$select "birth_date" from "public"."client_notes"$$, '42501', null, 'a signed-in user cannot read public.client_notes.birth_date');
reset role;

select extensions.has_table('public', 'saved_views', 'public.saved_views exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."saved_views"'::regclass), 'public.saved_views has row level security on');
select extensions.policies_are('public', 'saved_views', array['saved_views_select', 'saved_views_insert', 'saved_views_update', 'saved_views_delete', 'bsb_session_active'], 'public.saved_views has the policies for its scope');
select extensions.table_privs_are('public', 'saved_views', 'anon', array[]::text[], 'anon has no privileges on public.saved_views');
select extensions.table_privs_are('public', 'saved_views', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.saved_views');

with u as (
  insert into auth.users (id, email, aud, role, instance_id)
  values (gen_random_uuid(), 'bsb-app-tables-' || gen_random_uuid()::text || '@example.test', 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000')
  returning id
)
insert into "public"."saved_views" ("user_id", "name") select u.id, repeat('x', 1) from u;

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."saved_views"), 0, 'a signed-in user does not read a row of public.saved_views outside their scope');
select extensions.throws_ok($$insert into "public"."saved_views" ("user_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.saved_views outside their scope');
reset role;

select * from extensions.finish();
rollback;
