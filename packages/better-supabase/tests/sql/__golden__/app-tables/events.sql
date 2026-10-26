-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:8c2639fd81ae98dcc667ec714ec69767646459b409c03be705c97d0f06f5a64d
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

create table if not exists "public"."tasks" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "better_supabase"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists "public"."notes" (
  id uuid primary key default gen_random_uuid(),
  "organization_id" uuid not null references "better_supabase"."organizations" ("id") on delete cascade,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table "public"."tasks" add column if not exists "title" text not null;
alter table "public"."tasks" add column if not exists "status" text;

alter table "public"."notes" add column if not exists "body" text;

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
drop trigger if exists "bsb_updated_at" on "public"."tasks";
create trigger "bsb_updated_at" before update on "public"."tasks"
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
    perform "better_supabase".emit_event('task.created', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  if tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    select coalesce(array_agg(n.key order by n.key), array[]::text[]) into v_changed
      from jsonb_each(v_row) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if cardinality(v_changed) > 0 then
      perform "better_supabase".emit_event('task.updated', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status', 'changed', to_jsonb(v_changed)), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
    end if;
  end if;
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    perform "better_supabase".emit_event('task.deleted', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'task', 'subjectId', v_row ->> 'id', 'status', v_row -> 'status'), 'tasks/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  return null;
end;
$$;
revoke all on function "better_supabase"."tasks_emit_event"() from public, anon, authenticated;
drop trigger if exists "bsb_emit_event" on "public"."tasks";
create trigger "bsb_emit_event" after insert or update or delete on "public"."tasks"
  for each row execute function "better_supabase"."tasks_emit_event"();

alter table "public"."notes" enable row level security;
revoke all on "public"."notes" from anon, authenticated;
grant select, insert, update, delete on "public"."notes" to authenticated;
grant all on "public"."notes" to service_role;
drop policy if exists "notes_select" on "public"."notes";
create policy "notes_select" on "public"."notes" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "notes_insert" on "public"."notes";
create policy "notes_insert" on "public"."notes" for insert to authenticated with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "notes_update" on "public"."notes";
create policy "notes_update" on "public"."notes" for update to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write())) with check (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists "notes_delete" on "public"."notes";
create policy "notes_delete" on "public"."notes" for delete to authenticated using (("organization_id" in (select better_supabase.member_organization_ids())) and (select better_supabase.actor_may_write()));
drop policy if exists bsb_tenant_scope on "public"."notes";
drop policy if exists bsb_tenant_scope_select on "public"."notes";
create policy bsb_tenant_scope_select on "public"."notes" as restrictive
  for select to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_insert on "public"."notes";
create policy bsb_tenant_scope_insert on "public"."notes" as restrictive
  for insert to public
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_update on "public"."notes";
create policy bsb_tenant_scope_update on "public"."notes" as restrictive
  for update to public
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope_delete on "public"."notes";
create policy bsb_tenant_scope_delete on "public"."notes" as restrictive
  for delete to public
  using ("organization_id" in (select better_supabase.member_organization_ids()));
create index if not exists "notes_organization_id_idx" on "public"."notes" ("organization_id");
drop trigger if exists "bsb_updated_at" on "public"."notes";
create trigger "bsb_updated_at" before update on "public"."notes"
  for each row execute function better_supabase.set_updated_at();
create or replace function "better_supabase"."notes_emit_event"()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_changed text[];
begin
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    perform "better_supabase".emit_event('notes.deleted', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id'), 'notes/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  return null;
end;
$$;
revoke all on function "better_supabase"."notes_emit_event"() from public, anon, authenticated;
drop trigger if exists "bsb_emit_event" on "public"."notes";
create trigger "bsb_emit_event" after delete on "public"."notes"
  for each row execute function "better_supabase"."notes_emit_event"();

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:97a5cbfdeaeac54dc71fe397c33b6ecd48a3f696eadb75f1eb1678aa19a62503
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(18);

select extensions.has_table('public', 'tasks', 'public.tasks exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."tasks"'::regclass), 'public.tasks has row level security on');
select extensions.policies_are('public', 'tasks', array['tasks_select', 'tasks_insert', 'tasks_update', 'tasks_delete', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.tasks has the policies for its scope');
select extensions.col_has_check('public'::name, 'tasks'::name, 'status'::name, 'public.tasks.status has its check');
select extensions.table_privs_are('public', 'tasks', 'anon', array[]::text[], 'anon has no privileges on public.tasks');
select extensions.table_privs_are('public', 'tasks', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.tasks');

with o as (
  insert into "better_supabase"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."tasks" ("organization_id", "title") select o.id, repeat('x', 1) from o;
select extensions.has_trigger('public'::name, 'tasks'::name, 'bsb_emit_event'::name, 'public.tasks emits outbox events');
select extensions.ok(exists (select 1 from "better_supabase"."outbox_events" e where e."type" = 'task.created'), 'an insert into public.tasks emits task.created');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."tasks" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."tasks"), 0, 'a signed-in user does not read a row of public.tasks outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."tasks" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.tasks outside their scope even through an app policy using (true)');
reset role;

select extensions.has_table('public', 'notes', 'public.notes exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."notes"'::regclass), 'public.notes has row level security on');
select extensions.policies_are('public', 'notes', array['notes_select', 'notes_insert', 'notes_update', 'notes_delete', 'bsb_tenant_scope_select', 'bsb_tenant_scope_insert', 'bsb_tenant_scope_update', 'bsb_tenant_scope_delete'], 'public.notes has the policies for its scope');
select extensions.table_privs_are('public', 'notes', 'anon', array[]::text[], 'anon has no privileges on public.notes');
select extensions.table_privs_are('public', 'notes', 'authenticated', array['DELETE', 'INSERT', 'SELECT', 'UPDATE'], 'authenticated has the privileges for its scope on public.notes');

with o as (
  insert into "better_supabase"."organizations" ("name", "slug")
  values ('bsb-app-tables-test', 'bsb-app-tables-' || substr(md5(random()::text), 1, 8))
  returning "id" as id
)
insert into "public"."notes" ("organization_id") select o.id from o;
select extensions.has_trigger('public'::name, 'notes'::name, 'bsb_emit_event'::name, 'public.notes emits outbox events');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."notes" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.is((select count(*)::integer from "public"."notes"), 0, 'a signed-in user does not read a row of public.notes outside their scope even through an app policy using (true)');
select extensions.throws_ok($$insert into "public"."notes" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.notes outside their scope even through an app policy using (true)');
reset role;

select * from extensions.finish();
rollback;
