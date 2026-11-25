-- A restore writes the rows of an organization export back, as the service
-- role, on behalf of a tenant. It never writes the tables that decide access,
-- billing, usage or platform state, so an export someone edited can't make its
-- importer an owner or lift a quota. The run's creator needs the restore key
-- (organization.delete by default): the owner (…a1) has it, the member (…a2) not.
begin;
select plan(6);

insert into better_supabase.import_runs (id, tenant_id, source, created_by) values
  ('00000000-0000-4000-8000-0000000a7001', '00000000-0000-4000-8000-000000000001', 'restore', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-0000000a7002', '00000000-0000-4000-8000-000000000001', 'restore-member', '00000000-0000-4000-8000-0000000000a2');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select ok(
  not exists (select 1 from jsonb_array_elements(better_supabase.data_restore_tables()) x
    where x.value ->> 'name' in ('public.memberships', 'better_supabase.permission_overrides', 'better_supabase.usage_quotas',
      'better_supabase.billing_subscriptions', 'better_supabase.support_sessions', 'better_supabase.api_keys')),
  'the restore lists no membership, permission, usage, billing, support or key table'
);
select ok(
  exists (select 1 from jsonb_array_elements(better_supabase.data_restore_tables()) x where x.value ->> 'name' = 'better_supabase.companies'),
  'business tables stay restorable'
);
select throws_ok(
  $$select better_supabase.restore_data_row('00000000-0000-4000-8000-0000000a7001', jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001', 'key', 'm1',
    'data', jsonb_build_object('table', 'public.memberships', 'row', jsonb_build_object(
      'user_id', '00000000-0000-4000-8000-0000000000a2'))), 'm1')$$,
  '22023', null, 'a restore refuses a membership row'
);
select throws_ok(
  $$select better_supabase.restore_data_row('00000000-0000-4000-8000-0000000a7001', jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001', 'key', 'q1',
    'data', jsonb_build_object('table', 'better_supabase.usage_quotas', 'row', jsonb_build_object('meter', 'api.calls'))), 'q1')$$,
  '22023', null, 'a restore refuses a usage quota row'
);
select lives_ok(
  $$select better_supabase.restore_data_row('00000000-0000-4000-8000-0000000a7001', jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001', 'key', 'c1',
    'data', jsonb_build_object('table', 'better_supabase.tags', 'row', jsonb_build_object(
      'id', '00000000-0000-4000-8000-0000000a0901', 'kind', 'customer', 'name', 'Restored', 'slug', 'restored', 'rank', 'V',
      'created_at', now(), 'updated_at', now()))), 'c1')$$,
  'a restore writes a business row'
);

select throws_ok(
  $$select better_supabase.restore_data_row('00000000-0000-4000-8000-0000000a7002', jsonb_build_object(
    'tenant', '00000000-0000-4000-8000-000000000001', 'key', 'c2',
    'data', jsonb_build_object('table', 'better_supabase.tags', 'row', jsonb_build_object(
      'id', '00000000-0000-4000-8000-0000000a0902', 'kind', 'customer', 'name', 'Member', 'slug', 'member', 'rank', 'V',
      'created_at', now(), 'updated_at', now()))), 'c2')$$,
  '42501', null, 'a run a member started without the restore key writes nothing'
);

select * from finish();
rollback;
