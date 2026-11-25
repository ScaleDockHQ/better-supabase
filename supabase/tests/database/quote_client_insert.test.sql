-- A client that can insert quotes directly (through an app's Data API grant)
-- can't plant the public link token or a customer decision, and a variant must
-- point at a quote of its own organization. Acme is …0001, Globex is …0002.
begin;
select plan(4);

insert into better_supabase.quotes (id, tenant_id, number, identifier, title, currency)
values ('00000000-0000-4000-8000-0000000ce002', '00000000-0000-4000-8000-000000000002', 9001, 'Q-9001', 'Globex quote', 'EUR');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);

insert into better_supabase.quotes (id, tenant_id, number, identifier, title, currency, token_hash, decided_at, decided_by)
values ('00000000-0000-4000-8000-0000000ce001', '00000000-0000-4000-8000-000000000001', 9002, 'Q-9002', 'Planted', 'EUR', 'planted-hash', now(), 'Someone');

select is(
  (select token_hash from better_supabase.quotes where id = '00000000-0000-4000-8000-0000000ce001'),
  null, 'a client insert clears the public link token'
);
select is(
  (select decided_by from better_supabase.quotes where id = '00000000-0000-4000-8000-0000000ce001'),
  null, 'a client insert clears the customer decision'
);
select throws_ok(
  $$insert into better_supabase.quotes (tenant_id, number, identifier, title, currency, variant_of)
    values ('00000000-0000-4000-8000-000000000001', 9003, 'Q-9003', 'Variant', 'EUR', '00000000-0000-4000-8000-0000000ce002')$$,
  '22023', null, 'a variant can''t point at another organization''s quote'
);
select throws_ok(
  $$update better_supabase.quotes set variant_of = '00000000-0000-4000-8000-0000000ce002' where id = '00000000-0000-4000-8000-0000000ce001'$$,
  '22023', null, 'an update can''t point a quote at another organization''s quote'
);

select * from finish();
rollback;
