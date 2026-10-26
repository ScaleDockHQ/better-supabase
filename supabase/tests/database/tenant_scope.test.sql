-- The restrictive tenant scope on block tables (ADR 0099). The app adds its own
-- permissive policies that let everything through; they still can't reach
-- another organization's rows. Acme (…0001) has the seeded tags; the Globex
-- owner (…a3) isn't an Acme member.
begin;
select plan(6);

select ok(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'better_supabase' and tablename = 'tags'
      and policyname = 'bsb_tenant_scope_select' and permissive = 'RESTRICTIVE'
  ),
  'better_supabase.tags has a restrictive tenant scope'
);
select ok(
  exists (
    select 1 from pg_catalog.pg_policies
    where schemaname = 'better_supabase' and tablename = 'organization_settings'
      and policyname = 'bsb_tenant_scope_select' and permissive = 'RESTRICTIVE'
  ),
  'better_supabase.organization_settings has a restrictive tenant scope'
);

create policy app_reads_tags on better_supabase.tags for select to authenticated using (true);
create policy app_reads_taggings on better_supabase.taggings for select to authenticated using (true);
create policy app_writes_settings on better_supabase.organization_settings
  for all to authenticated using (true) with check (true);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.tags where tenant_id = '00000000-0000-4000-8000-000000000001'),
  2,
  'an app policy using (true) still reads the member''s own organization'
);

-- Globex owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.tags),
  0,
  'an app policy using (true) does not read another organization''s tags'
);
select is(
  (select count(*)::int from better_supabase.taggings),
  0,
  'an app policy using (true) does not read another organization''s taggings'
);
select throws_ok(
  $$insert into better_supabase.organization_settings (organization_id, key, value)
    values ('00000000-0000-4000-8000-000000000001', 'app.widened', 'true')$$,
  '42501', null,
  'an app policy with check (true) does not insert into another organization'
);

select * from finish();
rollback;
