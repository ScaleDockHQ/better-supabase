-- ERP known gaps 4 (ADR 0127, Intrastat): prepare_intrastat derives arrival
-- lines from purchase receipts like dispatch lines from shipments. A receipt
-- line counts when its detail names a member state; a manual arrival line for
-- the same variant and country wins and is reported as superseding the
-- receipt line; a derived line without a trade code is an exception. Run with
-- `supabase test db`.
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.pa', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve A', 'valve-a-intrastat', null, 'physical', null) ->> 'id', true);
select set_config('t.a', better_supabase.save_variant(current_setting('t.pa')::uuid, null, 'VALVE-A', null, 'Valve A', null, null, true, false, null) ->> 'id', true);
select set_config('t.pb', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve B', 'valve-b-intrastat', null, 'physical', null) ->> 'id', true);
select set_config('t.b', better_supabase.save_variant(current_setting('t.pb')::uuid, null, 'VALVE-B', null, 'Valve B', null, null, true, false, null) ->> 'id', true);
select set_config('t.pc', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve C', 'valve-c-intrastat', null, 'physical', null) ->> 'id', true);
select set_config('t.c', better_supabase.save_variant(current_setting('t.pc')::uuid, null, 'VALVE-C', null, 'Valve C', null, null, true, false, null) ->> 'id', true);
select better_supabase.set_variant_trade_code(current_setting('t.a')::uuid, '84818099');
select better_supabase.set_variant_trade_code(current_setting('t.c')::uuid, '84818099');
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'INTRA', 'Intrastat dock', null, null) ->> 'id', true);
select set_config('t.supplier', better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "Intrastat supplier"}') ->> 'id', true);

select set_config('t.po', better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, current_setting('t.l')::uuid, 'company',
  current_setting('t.supplier'), 'EUR', null,
  jsonb_build_array(
    jsonb_build_object('variantId', current_setting('t.a'), 'quantity', 4, 'unitCost', '1000'),
    jsonb_build_object('variantId', current_setting('t.b'), 'quantity', 2, 'unitCost', '500'),
    jsonb_build_object('variantId', current_setting('t.c'), 'quantity', 1, 'unitCost', '300')),
  null) ->> 'id', true);
select better_supabase.place_purchase_order(current_setting('t.po')::uuid);

-- A comes from Germany with a stated mass, B from France, C names no member state.
select better_supabase.receive_purchase_order(current_setting('t.po')::uuid, (
  select jsonb_agg(jsonb_build_object('lineId', x.id, 'quantity', x.quantity_ordered,
    'country', case x.variant_id::text when current_setting('t.a') then 'DE' when current_setting('t.b') then 'fr' end,
    'netMassKg', case x.variant_id::text when current_setting('t.a') then '12.5' end))
  from better_supabase.purchase_order_lines x where x.purchase_order_id = current_setting('t.po')::uuid));

select set_config('t.run1', better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date)::text, true);

select is(
  (select jsonb_agg(l ->> 'source' || ':' || (l ->> 'flow') || ':' || (l ->> 'country') order by l ->> 'country')
   from jsonb_array_elements(current_setting('t.run1')::jsonb -> 'lines') l),
  '["receipt:arrival:DE", "receipt:arrival:FR"]'::jsonb,
  'receipt lines that name a member state become arrival lines, the others do not'
);
select is(
  (select jsonb_build_array(l ->> 'tradeCode', l ->> 'netMassKg', l ->> 'quantity', l ->> 'value', l ->> 'currency')
   from jsonb_array_elements(current_setting('t.run1')::jsonb -> 'lines') l where l ->> 'country' = 'DE'),
  '["84818099", "12.500", "4.000000", "4000", "EUR"]'::jsonb,
  'an arrival line takes the trade code, the stated mass, the quantity and the cost value'
);
select is(
  (select jsonb_agg(e ->> 'code' order by e ->> 'code')
   from jsonb_array_elements(current_setting('t.run1')::jsonb -> 'exceptions') e
   where e ->> 'variantId' = current_setting('t.b')),
  '["INTRASTAT_NET_MASS_MISSING", "INTRASTAT_TRADE_CODE_MISSING"]'::jsonb,
  'a receipt line without a trade code is an exception, and so is a missing mass'
);
select is(
  (select count(*) from jsonb_array_elements(current_setting('t.run1')::jsonb -> 'exceptions') e where e ->> 'variantId' = current_setting('t.a')),
  0::bigint,
  'a complete receipt line is no exception'
);

-- Preparing again replaces the derived lines and does not duplicate them.
select is(
  jsonb_array_length(better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date) -> 'lines'),
  2,
  'preparing again derives the same two lines'
);

-- A manual arrival line for variant A from Germany wins over the receipt line.
select set_config('t.manual', better_supabase.save_intrastat_line('00000000-0000-4000-8000-000000000001', null, jsonb_build_object(
  'period', date_trunc('month', current_date)::date, 'flow', 'arrival', 'country', 'DE', 'variantId', current_setting('t.a'),
  'tradeCode', '84818099', 'netMassKg', '13', 'quantity', '4', 'value', '4100', 'currency', 'EUR')) ->> 'id', true);
select set_config('t.run2', better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date)::text, true);

select is(
  (select jsonb_agg(l ->> 'source' || ':' || (l ->> 'country') order by l ->> 'country')
   from jsonb_array_elements(current_setting('t.run2')::jsonb -> 'lines') l),
  '["manual:DE", "receipt:FR"]'::jsonb,
  'the manual line wins: the receipt line for the same variant and country is not derived'
);
select is(
  (select l -> 'supersedes' ->> 0 from jsonb_array_elements(current_setting('t.run2')::jsonb -> 'lines') l where l ->> 'source' = 'manual'),
  (select id::text from better_supabase.inventory_receipt_lines where variant_id = current_setting('t.a')::uuid),
  'the manual line is marked with the receipt line it supersedes'
);
select is(
  current_setting('t.run2')::jsonb -> 'superseded' -> 0 ->> 'manualLineId',
  current_setting('t.manual'),
  'the result lists what the manual line superseded'
);
select is(
  (select value::text from better_supabase.intrastat_lines where id = current_setting('t.manual')::uuid),
  '4100',
  'the manual line keeps its own figures'
);

-- A manual line stays when the month is prepared again, and the receipt line stays out.
select is(
  jsonb_array_length(better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date) -> 'lines'),
  2,
  'a third run keeps the manual line and still leaves the receipt line out'
);

-- Another organization sees none of it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.intrastat_lines),
  0::bigint,
  'another organization sees no Intrastat lines of Acme'
);

select * from finish();
rollback;
