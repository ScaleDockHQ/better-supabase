-- Bank accounts keep the organization's own order in position, which
-- save_bank_account sets and list_bank_accounts and the position sort read.
-- The Acme owner (…a1) manages bank accounts. Run with `supabase test db`.
begin;
select plan(5);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('a', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"name": "Alpha", "currency": "EUR", "position": 2}') ->> 'id')::uuid);
insert into ids values ('b', (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
  '{"name": "Beta", "currency": "EUR", "position": 1}') ->> 'id')::uuid);

select is(
  (select (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
    '{"name": "Gamma", "currency": "EUR"}') ->> 'position')::int),
  0,
  'a new account without a position takes 0'
);
select is(
  (select position from better_supabase.bank_accounts where id = (select id from ids where name = 'a')),
  2,
  'save stores the position'
);
select is(
  (select jsonb_agg(x ->> 'name') from jsonb_array_elements(better_supabase.list_bank_accounts('00000000-0000-4000-8000-000000000001')) x
    where x ->> 'name' in ('Alpha', 'Beta', 'Gamma')),
  '["Gamma", "Beta", "Alpha"]'::jsonb,
  'list_bank_accounts orders by position, then name'
);
select is(
  (better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001',
    '{"holder": "Acme BV"}', (select id from ids where name = 'a')) ->> 'position')::int,
  2,
  'an update without position keeps it'
);
select throws_ok(
  $$select better_supabase.save_bank_account('00000000-0000-4000-8000-000000000001', '{"position": -1}', (select id from ids where name = 'b'))$$,
  '22023',
  null,
  'a negative position is refused'
);

select * from finish();
rollback;
