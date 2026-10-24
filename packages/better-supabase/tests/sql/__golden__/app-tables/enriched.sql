-- ==== schema supabase/schemas/900_better_supabase_app_tables.sql
-- better-supabase module: app-tables
-- @bsb-tables
-- @bsb-hash sha256:7ba60eacd3839ee4fb1f5297e8c6c438ccfc47429ef31b072f39f11a4a47b193
-- The tables the app owns, from `appTables`, in public.
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

-- "public"."invoices" is the app's table (supabase/schemas/010_app.sql): tables.invoices adds only the columns it lacks.
alter table "public"."invoices" add column if not exists "organization_id" uuid references "better_supabase"."organizations" ("id") on delete cascade;
alter table "public"."invoices" add column if not exists updated_at timestamptz not null default now();
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = '"public"."invoices"'::regclass and conname = 'invoices_organization_id_not_null'
  ) then
    alter table "public"."invoices" add constraint "invoices_organization_id_not_null"
      check ("organization_id" is not null) not valid;
  end if;
end;
$$;

alter table "public"."invoices" add column if not exists "total_minor" bigint;
alter table "public"."invoices" add column if not exists "status" text not null default 'draft';

alter table "public"."invoices" enable row level security;
-- "public"."invoices" keeps the app's own grants; these add what the scope needs.
grant select, insert, update, delete on "public"."invoices" to authenticated;
grant all on "public"."invoices" to service_role;
drop policy if exists "bsb_invoices_select" on "public"."invoices";
create policy "bsb_invoices_select" on "public"."invoices" for select to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "bsb_invoices_insert" on "public"."invoices";
create policy "bsb_invoices_insert" on "public"."invoices" for insert to authenticated with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "bsb_invoices_update" on "public"."invoices";
create policy "bsb_invoices_update" on "public"."invoices" for update to authenticated using ("organization_id" in (select better_supabase.member_organization_ids())) with check ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists "bsb_invoices_delete" on "public"."invoices";
create policy "bsb_invoices_delete" on "public"."invoices" for delete to authenticated using ("organization_id" in (select better_supabase.member_organization_ids()));
drop policy if exists bsb_tenant_scope on "public"."invoices";
create policy bsb_tenant_scope on "public"."invoices" as restrictive
  for all to authenticated
  using ("organization_id" in (select better_supabase.member_organization_ids()))
  with check ("organization_id" in (select better_supabase.member_organization_ids()));
create index if not exists "invoices_organization_id_idx" on "public"."invoices" ("organization_id");
drop trigger if exists "bsb_updated_at" on "public"."invoices";
create trigger "bsb_updated_at" before update on "public"."invoices"
  for each row execute function better_supabase.set_updated_at();
create or replace function "better_supabase"."invoices_emit_event"()
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
    perform "better_supabase".emit_event('invoice.created', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'invoice', 'subjectId', v_row ->> 'id'), 'invoices/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  if tg_op = 'UPDATE' then
    v_row := to_jsonb(new);
    select coalesce(array_agg(n.key order by n.key), array[]::text[]) into v_changed
      from jsonb_each(v_row) n
      join jsonb_each(to_jsonb(old)) o on o.key = n.key
     where n.value is distinct from o.value and n.key <> 'updated_at';
    if cardinality(v_changed) > 0 then
      perform "better_supabase".emit_event('invoice.updated', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'invoice', 'subjectId', v_row ->> 'id', 'changed', to_jsonb(v_changed)), 'invoices/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
    end if;
  end if;
  if tg_op = 'DELETE' then
    v_row := to_jsonb(old);
    perform "better_supabase".emit_event('invoice.deleted', jsonb_build_object('id', v_row -> 'id', 'organizationId', v_row -> 'organization_id', 'subjectType', 'invoice', 'subjectId', v_row ->> 'id'), 'invoices/' || (v_row ->> 'id'), (v_row ->> 'organization_id')::text, null, 'better-supabase/app-tables');
  end if;
  return null;
end;
$$;
revoke all on function "better_supabase"."invoices_emit_event"() from public, anon, authenticated;
drop trigger if exists "bsb_emit_event" on "public"."invoices";
create trigger "bsb_emit_event" after insert or update or delete on "public"."invoices"
  for each row execute function "better_supabase"."invoices_emit_event"();

-- ==== test supabase/tests/900_better_supabase_app_tables.test.sql
-- better-supabase module: app-tables
-- @bsb-block-test app-tables
-- @bsb-hash sha256:3cf1f8e1b2fa0b599de0eb0af0d79b384624ad0c082a34f53c0c4fb411dec88d
-- Managed by `better-supabase upgrade`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `appTables` in better-supabase.config.ts.

begin;
create extension if not exists pgtap with schema extensions;
select extensions.plan(9);

select extensions.has_table('public', 'invoices', 'public.invoices exists');
select extensions.ok((select c.relrowsecurity from pg_catalog.pg_class c where c.oid = '"public"."invoices"'::regclass), 'public.invoices has row level security on');
select extensions.ok(array['bsb_invoices_select', 'bsb_invoices_insert', 'bsb_invoices_update', 'bsb_invoices_delete', 'bsb_tenant_scope']::name[] <@ array(select p.policyname from pg_catalog.pg_policies p where p.schemaname = 'public' and p.tablename = 'invoices'), 'public.invoices has the policies for its scope');
select extensions.has_column('public', 'invoices', 'organization_id', 'public.invoices has the scope column organization_id');
select extensions.ok(exists (select 1 from pg_catalog.pg_constraint k where k.conrelid = '"public"."invoices"'::regclass and k.conname = 'invoices_organization_id_not_null' and k.contype = 'c'), 'new rows of public.invoices must fill organization_id');
select extensions.ok(array['DELETE', 'INSERT', 'SELECT', 'UPDATE']::text[] <@ array(select g.privilege_type::text from information_schema.role_table_grants g where g.table_schema = 'public' and g.table_name = 'invoices' and g.grantee = 'authenticated'), 'authenticated has the privileges for its scope on public.invoices');
select extensions.has_trigger('public'::name, 'invoices'::name, 'bsb_emit_event'::name, 'public.invoices emits outbox events');

-- An app's own permissive policy can't widen the tenant scope.
create policy bsb_test_app_widens on "public"."invoices" for all to authenticated using (true) with check (true);

select set_config('request.jwt.claims', json_build_object('sub', gen_random_uuid(), 'role', 'authenticated')::text, true);
set local role authenticated;
select extensions.skip('public.invoices is the app''s table, so the read test can''t insert a row of another tenant', 1);
select extensions.throws_ok($$insert into "public"."invoices" ("organization_id") values (gen_random_uuid())$$, '42501', null, 'a signed-in user cannot insert a row of public.invoices outside their scope even through an app policy using (true)');
reset role;

select * from extensions.finish();
rollback;
