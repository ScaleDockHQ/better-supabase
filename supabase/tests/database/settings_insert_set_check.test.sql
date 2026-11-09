-- The organization settings insert policy checks the tenant with the set of
-- the caller's tenants (tenant_ids_with) instead of a per-row can() call, and
-- still lets an admin insert and refuses another tenant's member (ADR 0426).
begin;
select plan(4);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'better_supabase' and tablename = 'organization_settings' and cmd = 'INSERT'
      and with_check like '%better_supabase.can(%'),
  0,
  'no insert policy on organization_settings calls can() per row'
);
select ok(
  (select bool_and(with_check like '%tenant_ids_with%') from pg_policies
    where schemaname = 'better_supabase' and tablename = 'organization_settings' and cmd = 'INSERT' and permissive = 'PERMISSIVE'),
  'the permissive insert policy uses tenant_ids_with'
);

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select lives_ok(
  $$insert into better_supabase.organization_settings (tenant_id, key, value) values ('00000000-0000-4000-8000-000000000001', 'scale.check', '{"a":1}')$$,
  'an admin inserts a setting'
);
select throws_ok(
  $$insert into better_supabase.organization_settings (tenant_id, key, value) values ('00000000-0000-4000-8000-000000000002', 'scale.check', '{"a":1}')$$,
  '42501',
  null,
  'a member of another tenant is refused'
);

select * from finish();
rollback;
