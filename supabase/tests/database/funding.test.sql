-- The funding module against the seed: the Acme owner (…a1) adds a product,
-- awards a customer 2 hours a week from a funder, registers care that runs
-- over, approves it and claims it, the funder rejects the line and the care
-- goes back for correction; the Acme member (…a2) registers care but can't
-- approve or claim, and the Globex owner (…a3) sees none of it.
-- Run with `supabase test db`.
begin;
select plan(22);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('funding_products', 'funding_awards', 'funding_deliveries', 'funding_claims', 'funding_claim_lines')
     and rowsecurity),
  5::bigint,
  'the funding tables have RLS enabled'
);
select table_privs_are('better_supabase', 'funding_awards', 'anon', '{}'::text[],
  'anon has no privileges on awards');
select table_privs_are('better_supabase', 'funding_deliveries', 'authenticated', array['SELECT'],
  'authenticated only reads deliveries; writes go through the functions');
select ok(
  not has_function_privilege('authenticated',
    'better_supabase.register_funding_deliveries_from_time(uuid, date, date)', 'execute'),
  'only the service role registers deliveries from time entries'
);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
insert into ids values ('funder', gen_random_uuid()), ('other', gen_random_uuid());
insert into better_supabase.companies (id, tenant_id, name, lifecycle, roles) values
  ((select id from ids where name = 'funder'), '00000000-0000-4000-8000-000000000001', 'Zorgkantoor', 'customer', '{funder}'),
  ((select id from ids where name = 'other'), '00000000-0000-4000-8000-000000000001', 'Initech', 'customer', '{}');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids values ('product', (better_supabase.save_funding_product(
  '00000000-0000-4000-8000-000000000001', 'H300', 'Individual support', 'hour', 6850, 'EUR') ->> 'id')::uuid);

select throws_ok(
  $$select better_supabase.save_funding_product('00000000-0000-4000-8000-000000000001', 'H300', 'Again', 'hour', 1, 'EUR')$$,
  '22023',
  null,
  'a product code is unique in an organization'
);
select throws_ok(
  $$select better_supabase.save_funding_award('00000000-0000-4000-8000-000000000001', 'customer',
    '00000000-0000-4000-8000-00000000a001', jsonb_build_object('funderId', (select id from ids where name = 'other'),
    'productId', (select id from ids where name = 'product'), 'units', 2, 'period', 'week', 'startsOn', current_date - 14))$$,
  '22023',
  null,
  'a contact without the funder role cannot fund an award'
);

insert into ids values ('award', (better_supabase.save_funding_award('00000000-0000-4000-8000-000000000001', 'customer',
  '00000000-0000-4000-8000-00000000a001', jsonb_build_object('funderId', (select id from ids where name = 'funder'),
  'productId', (select id from ids where name = 'product'), 'units', 2, 'period', 'week',
  'startsOn', current_date - 14, 'reference', 'WLZ-1')) ->> 'id')::uuid);

select is(
  (select status from better_supabase.funding_awards where id = (select id from ids where name = 'award')),
  'active',
  'an award starts active'
);

insert into ids values ('first', (better_supabase.register_funding_delivery((select id from ids where name = 'award'),
  current_date - 7, 1.5, 'manual', 'visit-1') ->> 'id')::uuid);
select is(
  (better_supabase.register_funding_delivery((select id from ids where name = 'award'),
    current_date - 7, 1.5, 'manual', 'visit-1') ->> 'id')::uuid,
  (select id from ids where name = 'first'),
  'registering a source again returns its delivery'
);
insert into ids values ('second', (better_supabase.register_funding_delivery((select id from ids where name = 'award'),
  current_date - 7, 1) ->> 'id')::uuid);

reset role;
select ok(
  exists (select 1 from better_supabase.outbox_events
    where type = 'funding_award.exceeded'
      and payload ->> 'fundingAwardId' = (select id from ids where name = 'award')::text),
  'going over the weekly units records funding_award.exceeded'
);
set local role authenticated;
select ok(
  exists (select 1 from jsonb_array_elements(better_supabase.funding_award_usage(
    (select id from ids where name = 'award')) -> 'periods') p where (p ->> 'over')::numeric = 0.5),
  'usage shows the period that ran half an hour over'
);
select throws_ok(
  $$select better_supabase.register_funding_delivery((select id from ids where name = 'award'), current_date - 30, 1)$$,
  '22023',
  null,
  'care before the award starts is refused'
);

select throws_ok(
  $$select better_supabase.build_funding_claim('00000000-0000-4000-8000-000000000001',
    (select id from ids where name = 'funder'), current_date - 14, current_date, 'test')$$,
  '22023',
  null,
  'a claim needs approved deliveries'
);
select is(
  better_supabase.approve_funding_deliveries(array[(select id from ids where name = 'first'), (select id from ids where name = 'second')]),
  2,
  'approving changes both deliveries'
);

insert into ids values ('claim', (better_supabase.build_funding_claim('00000000-0000-4000-8000-000000000001',
  (select id from ids where name = 'funder'), current_date - 14, current_date, 'test') ->> 'id')::uuid);

select is(
  (select total from better_supabase.funding_claims where id = (select id from ids where name = 'claim')),
  17125::bigint,
  'the claim prices 2.5 hours at the product rate'
);
select is(
  (select count(*) from better_supabase.funding_deliveries
   where award_id = (select id from ids where name = 'award') and status = 'claimed'),
  2::bigint,
  'the claim holds its deliveries'
);
select throws_ok(
  $$select better_supabase.approve_funding_deliveries(array[(select id from ids where name = 'first')], false)$$,
  '22023',
  null,
  'a delivery a claim holds cannot change'
);
select throws_ok(
  $$select better_supabase.record_funding_claim_response((select id from ids where name = 'claim'), '[]')$$,
  '22023',
  null,
  'a draft claim takes no response'
);

select is(
  better_supabase.mark_funding_claim_sent((select id from ids where name = 'claim'), 'VZ-77', repeat('a', 64)) ->> 'status',
  'sent',
  'marking the claim sent keeps the reference'
);
select is(
  better_supabase.record_funding_claim_response((select id from ids where name = 'claim'),
    jsonb_build_array(jsonb_build_object('lineId',
      (select id from better_supabase.funding_claim_lines where claim_id = (select id from ids where name = 'claim')),
      'status', 'rejected', 'rejectionCode', '8001'))) ->> 'status',
  'rejected',
  'a claim whose every line is rejected is rejected'
);
select is(
  (select count(*) from better_supabase.funding_deliveries
   where award_id = (select id from ids where name = 'award') and status = 'approved'),
  2::bigint,
  'the deliveries of a rejected line go back to approved'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.approve_funding_deliveries(array[(select id from ids where name = 'first')])$$,
  '42501',
  null,
  'a member without funding.approve cannot approve care'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  (select count(*) from better_supabase.funding_awards) + (select count(*) from better_supabase.funding_claims),
  0::bigint,
  'another organization sees no awards or claims'
);

reset role;

select * from finish();
rollback;
