-- Requests for quotation on the fixture. The Acme owner (…a1) asks two
-- suppliers to quote one line, compares the quotes and awards the cheaper one,
-- which creates the draft purchase order. A supplier that is not marked as one,
-- a quote on a draft request and an incomplete award are refused. The Acme
-- member (…a2) holds no rfqs keys and sees nothing, and the Globex owner (…a3)
-- sees none of it. Run with `supabase test db`.
begin;
select plan(21);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('rfqs', 'rfq_lines', 'rfq_suppliers', 'rfq_quotes', 'rfq_quote_lines')
     and rowsecurity),
  5::bigint,
  'the rfqs tables have RLS enabled'
);
select table_privs_are('better_supabase', 'rfqs', 'anon', '{}'::text[], 'anon has no privileges on requests');
select table_privs_are('better_supabase', 'rfq_quotes', 'anon', '{}'::text[], 'anon has no privileges on quotes');
select table_privs_are('better_supabase', 'rfq_quote_lines', 'authenticated', array['SELECT'], 'members can only read quote lines');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Pallets', 'pallets-rfq', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'PALLET-RFQ', null, 'Pallet', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'RFQ', 'Receiving dock', null, null) ->> 'id', true);
select set_config('t.a', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Cheap pallets"}') ->> 'id', true);
select set_config('t.b', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Fast pallets"}') ->> 'id', true);
select set_config('t.c', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Plain customer"}') ->> 'id', true);
select better_supabase.set_party_roles(current_setting('t.a')::uuid, array['supplier']);
select better_supabase.set_party_roles(current_setting('t.b')::uuid, array['supplier']);
select better_supabase.set_party_roles(current_setting('t.c')::uuid, array['customer']);

select set_config(
  't.rfq',
  better_supabase.create_rfq(
    '00000000-0000-4000-8000-000000000001',
    '{"title": "Pallets for Q4", "currency": "eur"}'::jsonb,
    jsonb_build_array(jsonb_build_object('description', 'Euro pallet', 'quantity', 10, 'variantId', current_setting('t.v')))) ->> 'id',
  true
);
select is(
  (select jsonb_build_array(r ->> 'number', r ->> 'status', r ->> 'currency')
   from (select better_supabase.get_rfq(current_setting('t.rfq')::uuid) r) x),
  '["RFQ-1", "draft", "EUR"]'::jsonb,
  'a request is numbered, starts as a draft and keeps an upper case currency'
);
select set_config('t.line', (better_supabase.get_rfq(current_setting('t.rfq')::uuid) -> 'lines' -> 0 ->> 'id'), true);

select throws_ok(
  format($$select better_supabase.open_rfq(%L)$$, current_setting('t.rfq')),
  '22023',
  null,
  'a request without a supplier does not open'
);
select throws_ok(
  format($$select better_supabase.invite_rfq_supplier(%L, 'company', %L)$$, current_setting('t.rfq'), current_setting('t.c')),
  '22023',
  null,
  'a party that is not a supplier is not invited'
);
select set_config('t.ia', better_supabase.invite_rfq_supplier(current_setting('t.rfq')::uuid, 'company', current_setting('t.a')) ->> 'id', true);
select set_config('t.ib', better_supabase.invite_rfq_supplier(current_setting('t.rfq')::uuid, 'company', current_setting('t.b')) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.invite_rfq_supplier(%L, 'company', %L)$$, current_setting('t.rfq'), current_setting('t.a')),
  '22023',
  null,
  'a supplier is invited once'
);
select throws_ok(
  format($$select better_supabase.record_rfq_quote(%L, %L, '{}'::jsonb, jsonb_build_array(jsonb_build_object('lineId', %L, 'unitAmount', '1250')))$$,
    current_setting('t.rfq'), current_setting('t.ia'), current_setting('t.line')),
  '55000',
  null,
  'a draft request takes no quotes'
);
select is(
  (better_supabase.open_rfq(current_setting('t.rfq')::uuid) ->> 'status'),
  'open',
  'a request with a line and suppliers opens'
);

select is(
  (better_supabase.record_rfq_quote(
    current_setting('t.rfq')::uuid, current_setting('t.ia')::uuid, '{"leadTimeDays": 14}'::jsonb,
    jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'unitAmount', '1250'))) ->> 'total'),
  '12500',
  'a quote totals its unit amounts times the quantities'
);
select set_config('t.qb', better_supabase.record_rfq_quote(
  current_setting('t.rfq')::uuid, current_setting('t.ib')::uuid, '{"leadTimeDays": 3}'::jsonb,
  jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'unitAmount', '1400'))) ->> 'id', true);
select is(
  (better_supabase.record_rfq_quote(
    current_setting('t.rfq')::uuid, current_setting('t.ib')::uuid, '{"leadTimeDays": 3}'::jsonb,
    jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'unitAmount', '1450'))) ->> 'revision'),
  '2',
  'quoting again replaces the prices and raises the revision'
);
select throws_ok(
  format($$select better_supabase.record_rfq_quote(%L, %L, '{}'::jsonb, jsonb_build_array(jsonb_build_object('lineId', %L, 'unitAmount', '1')))$$,
    current_setting('t.rfq'), current_setting('t.ia'), gen_random_uuid()),
  '22023',
  null,
  'a price for a line outside the request is refused'
);
select is(
  (select jsonb_build_array(q ->> 'supplierId', q ->> 'total', (q ->> 'lowest')::boolean)
   from jsonb_array_elements(better_supabase.compare_rfq(current_setting('t.rfq')::uuid) -> 'quotes') q
   where (q ->> 'lowest')::boolean),
  jsonb_build_array(current_setting('t.a'), '12500', true),
  'the comparison marks the cheapest complete quote'
);

select better_supabase.close_rfq(current_setting('t.rfq')::uuid);
select throws_ok(
  format($$select better_supabase.record_rfq_quote(%L, %L, '{}'::jsonb, jsonb_build_array(jsonb_build_object('lineId', %L, 'unitAmount', '1')))$$,
    current_setting('t.rfq'), current_setting('t.ia'), current_setting('t.line')),
  '55000',
  null,
  'a closed request takes no quotes'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.get_rfq(%L)$$, current_setting('t.rfq')),
  'P0002',
  null,
  'a member without rfqs keys cannot see the request'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  (better_supabase.award_rfq(current_setting('t.rfq')::uuid, current_setting('t.qb')::uuid, current_setting('t.l')::uuid) ->> 'status'),
  'awarded',
  'a complete quote is awarded'
);
select isnt(
  (better_supabase.get_rfq(current_setting('t.rfq')::uuid) ->> 'purchaseOrderId'),
  null,
  'the award creates a purchase order'
);
select is(
  (select array_agg(q ->> 'status' order by q ->> 'status') from jsonb_array_elements(better_supabase.get_rfq(current_setting('t.rfq')::uuid) -> 'quotes') q),
  array['awarded', 'rejected'],
  'the awarded quote wins and the other is rejected'
);
select throws_ok(
  format($$select better_supabase.cancel_rfq(%L, 'changed our mind')$$, current_setting('t.rfq')),
  '55000',
  null,
  'an awarded request cannot be cancelled'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.list_rfqs('00000000-0000-4000-8000-000000000002')),
  0,
  'another organization sees no requests'
);

select * from finish();
rollback;
