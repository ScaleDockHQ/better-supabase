-- Bank accounts take a holder and a primary flag (ADR 0663). The Acme owner
-- (…a1) makes a second account primary, which clears the first one's flag;
-- archiving a primary account clears its flag; the member (…a2) can't change
-- accounts. Run with `supabase test db`.
begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('one', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"name": "Main", "holder": "Acme BV", "currency": "EUR", "primary": true}') ->> 'id')::uuid);
insert into ids values ('two', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"name": "Savings", "currency": "EUR"}') ->> 'id')::uuid);
insert into ids values ('usd', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"name": "Dollars", "currency": "USD", "primary": true}') ->> 'id')::uuid);

select is(
  (select jsonb_build_array(holder, is_primary) from better_supabase.bank_accounts where id = (select id from ids where name = 'one')),
  '["Acme BV", true]'::jsonb,
  'an account keeps its holder and its primary flag'
);

select better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"primary": true}', (select id from ids where name = 'two'));
select is(
  (select jsonb_agg(is_primary order by name) from better_supabase.bank_accounts where id in (select id from ids where name in ('one', 'two'))),
  '[false, true]'::jsonb,
  'making Savings primary clears Main (rows ordered by name)'
);
select is(
  (select is_primary from better_supabase.bank_accounts where id = (select id from ids where name = 'usd')),
  true,
  'the primary flag is per currency'
);

select is(
  (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
    '{"archived": true}', (select id from ids where name = 'two')) ->> 'primary')::boolean,
  false,
  'archiving a primary account clears its flag'
);
select is(
  (select count(*) from better_supabase.bank_accounts where is_primary and currency = 'EUR'),
  0::bigint,
  'no primary EUR account is left'
);
select is(
  (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
    '{"holder": null}', (select id from ids where name = 'one')) ->> 'holder'),
  null,
  'a null holder clears it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001', '{"primary": true}', (select id from ids where name = 'one'))$$,
  '42501',
  null,
  'a member can''t change accounts'
);

select * from finish();
rollback;
