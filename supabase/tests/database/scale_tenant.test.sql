-- A member with many memberships, and a tenant with thousands of customers,
-- reading through RLS. The rows exist only for this test and roll back.
-- Thresholds are wall-clock ceilings, not a benchmark median.
begin;
select plan(3);

insert into public.organizations (id, name, slug)
select
  ('00000000-0000-4000-8100-' || lpad(to_hex(i), 12, '0'))::uuid,
  'Scale org ' || i,
  'scale-test-' || i
from generate_series(1, 149) as series(i);

insert into public.memberships (organization_id, user_id, role)
select
  organization.id,
  '00000000-0000-4000-8000-0000000000a1',
  (select roles.id from better_supabase.roles as roles where roles.key = 'member' limit 1)
from public.organizations as organization
where organization.slug like 'scale-test-%';

-- seed.sql gives this user Acme and Globex, so the scale rows make 151.
select is(
  (select count(*)::integer from public.memberships
    where user_id = '00000000-0000-4000-8000-0000000000a1'),
  151,
  'the admin holds 151 memberships'
);

insert into public.customers (organization_id, name, status)
select
  '00000000-0000-4000-8000-000000000001',
  'Scale test ' || i,
  'lead'
from generate_series(1, 5000) as series(i);

create function pg_temp.claims_ms()
returns double precision
language plpgsql
as $$
declare
  started timestamptz := clock_timestamp();
begin
  perform better_supabase.membership_claims('00000000-0000-4000-8000-0000000000a1');
  return extract(epoch from clock_timestamp() - started) * 1000;
end;
$$;

create function pg_temp.page_ms()
returns double precision
language plpgsql
as $$
declare
  started timestamptz := clock_timestamp();
begin
  perform set_config(
    'request.jwt.claims',
    '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
    true
  );
  perform id from public.customers
  where organization_id = '00000000-0000-4000-8000-000000000001'
  order by created_at desc, id desc
  limit 50;
  return extract(epoch from clock_timestamp() - started) * 1000;
end;
$$;

select ok(
  pg_temp.claims_ms() < 500,
  'membership_claims for 151 memberships stays under 500 ms'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

set local role authenticated;

select ok(
  pg_temp.page_ms() < 200,
  'a 50-row customer page through RLS stays under 200 ms'
);

select * from finish();
rollback;
