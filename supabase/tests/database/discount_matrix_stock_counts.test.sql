-- The discount matrix, stock count documents and Intrastat lines on the
-- fixture's access contract. The admin (…00a1) of Acme (…0001) prices a
-- customer group against a product group, counts a location and ships to
-- another member state. Globex (…00b1) sees none of it.
begin;
select plan(24);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Pump', 'pump', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.p')::uuid, null, 'PUMP-1', null, 'Pump', null, 500, true, false, null) ->> 'id', true);
select set_config('t.p2', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Hose', 'hose', null, 'physical', null) ->> 'id', true);
select set_config('t.v2', better_supabase.save_variant(current_setting('t.p2')::uuid, null, 'HOSE-1', null, 'Hose', null, 200, true, false, null) ->> 'id', true);
select set_config('t.party', '00000000-0000-4000-8000-00000000c001', true);
select set_config('t.other', '00000000-0000-4000-8000-00000000c002', true);

-- Groups.
select set_config('t.cg', better_supabase.save_discount_group('00000000-0000-4000-8000-000000000001', null, 'customer', 'DEALER', 'Dealers') ->> 'id', true);
select set_config('t.pg', better_supabase.save_discount_group('00000000-0000-4000-8000-000000000001', null, 'product', 'PUMPS', 'Pumps') ->> 'id', true);
select set_config('t.pg2', better_supabase.save_discount_group('00000000-0000-4000-8000-000000000001', null, 'product', 'HOSES', 'Hoses') ->> 'id', true);

select throws_ok(
  $$select better_supabase.save_discount_group('00000000-0000-4000-8000-000000000001', null, 'customer', 'DEALER', 'Again')$$,
  null,
  null,
  'a group code is unique per kind'
);
select throws_ok(
  $$select better_supabase.save_discount_group('00000000-0000-4000-8000-000000000001', null, 'region', 'EU', 'EU')$$,
  '22023',
  null,
  'a group is a customer or product group'
);
select is(better_supabase.set_party_discount_group('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.cg')::uuid), true, 'a customer joins a group');
select is(better_supabase.set_variant_discount_group(current_setting('t.v')::uuid, current_setting('t.pg')::uuid), true, 'a variant joins a product group');
select is(better_supabase.set_variant_discount_group(current_setting('t.v2')::uuid, current_setting('t.pg2')::uuid), true, 'another variant joins another group');

-- Rules.
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('customerGroupId', current_setting('t.cg'), 'discountBps', 1000));
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('productGroupId', current_setting('t.pg'), 'discountBps', 500));
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('customerGroupId', current_setting('t.cg'), 'productGroupId', current_setting('t.pg'), 'discountBps', 2000));
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('customerGroupId', current_setting('t.cg'), 'productGroupId', current_setting('t.pg'), 'minQuantity', '10', 'discountBps', 2500));
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('customerGroupId', current_setting('t.cg'), 'productGroupId', current_setting('t.pg'), 'validFrom', '2020-01-01', 'validTo', '2020-12-31', 'discountBps', 3000));
select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, jsonb_build_object('productGroupId', current_setting('t.pg2'), 'fixedPrice', '900', 'currency', 'EUR', 'discountBps', 0));

select throws_ok(
  format($$select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, %L::jsonb)$$, '{"discountBps": 10001}'),
  '22023',
  null,
  'a discount is at most 10000 basis points'
);
select throws_ok(
  format($$select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, %L::jsonb)$$, '{"fixedPrice": "900"}'),
  '22023',
  null,
  'a fixed price needs its currency'
);
select throws_ok(
  format($$select better_supabase.save_discount_rule('00000000-0000-4000-8000-000000000001', null, %L::jsonb)$$, '{"validFrom": "2026-02-01", "validTo": "2026-01-01"}'),
  '22023',
  null,
  'a validity window ends after it starts'
);

select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.v')::uuid, 1, current_date) ->> 'discountBps')::integer,
  2000,
  'the rule for both groups beats the one for a single group'
);
select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.v')::uuid, 10, current_date) ->> 'discountBps')::integer,
  2500,
  'a quantity break applies from its minimum'
);
select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.v')::uuid, 9.999, current_date) ->> 'discountBps')::integer,
  2000,
  'a quantity below the break keeps the base rule'
);
select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.v')::uuid, 1, date '2020-06-01') ->> 'discountBps')::integer,
  3000,
  'a rule inside its validity window beats an open one'
);
select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.party'), current_setting('t.v')::uuid, 1, date '2021-06-01') ->> 'discountBps')::integer,
  2000,
  'a rule outside its window does not apply'
);
select is(
  (better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.other'), current_setting('t.v')::uuid, 1, current_date) ->> 'discountBps')::integer,
  500,
  'a customer outside the group gets the product group rule'
);
select is(
  better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.other'), current_setting('t.v2')::uuid, 1, current_date, 'EUR') ->> 'fixedPrice',
  '900',
  'a fixed price rule returns the price in its currency'
);
select is(
  better_supabase.resolve_line_discount('00000000-0000-4000-8000-000000000001', current_setting('t.other'), current_setting('t.v2')::uuid, 1, current_date, 'USD') ->> 'ruleId',
  null,
  'a fixed price in another currency is skipped'
);
select throws_ok(
  format($$select better_supabase.delete_discount_group(%L)$$, current_setting('t.cg')),
  null,
  null,
  'a group a rule uses can not be deleted'
);

-- Stock counts.
select set_config('t.loc', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH1', 'Warehouse', null, null) ->> 'id', true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.loc')::uuid, 10, 'receipt', 'in');
select set_config('t.count', better_supabase.open_stock_count('00000000-0000-4000-8000-000000000001', current_setting('t.loc')::uuid, '{"note": "Year end"}') ->> 'id', true);
select is(
  (better_supabase.record_count_line(current_setting('t.count')::uuid, jsonb_build_object('variantId', current_setting('t.v'), 'counted', '7')) ->> 'variance')::numeric,
  -3::numeric,
  'a line takes the variance of counted minus expected'
);
select is(
  (better_supabase.post_stock_count(current_setting('t.count')::uuid) ->> 'posted')::boolean,
  true,
  'posting a count writes its adjustments'
);
select is(
  (select on_hand from better_supabase.stock_levels where variant_id = current_setting('t.v')::uuid and location_id = current_setting('t.loc')::uuid),
  7::numeric,
  'the count moved on-hand to the counted quantity'
);
select is(
  (better_supabase.post_stock_count(current_setting('t.count')::uuid) ->> 'posted')::boolean
    or (select on_hand <> 7 from better_supabase.stock_levels where variant_id = current_setting('t.v')::uuid and location_id = current_setting('t.loc')::uuid),
  false,
  'posting again adjusts nothing'
);

-- Intrastat.
select better_supabase.set_variant_trade_code(current_setting('t.v')::uuid, '84137030');
select better_supabase.adjust_stock(current_setting('t.v2')::uuid, current_setting('t.loc')::uuid, 5, 'receipt', 'in');
select set_config('t.ship', better_supabase.create_shipment(
  '00000000-0000-4000-8000-000000000001',
  '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}',
  '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}',
  '[{"weightGrams": 1000}]'
) ->> 'id', true);
select better_supabase.set_shipment_lines(current_setting('t.ship')::uuid, jsonb_build_array(
  jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.loc'), 'quantity', '1', 'detail', '{"value": "5000", "currency": "EUR"}'::jsonb),
  jsonb_build_object('variantId', current_setting('t.v2'), 'locationId', current_setting('t.loc'), 'quantity', '2')
));
select better_supabase.set_shipment_label(current_setting('t.ship')::uuid, 'flat-rate', 'standard', 'FR1', 'lbl_1', 695, 'EUR');
select set_config('t.intrastat', better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date)::text, true);
select is(
  (select jsonb_agg(l ->> 'flow' || ':' || (l ->> 'country')) from jsonb_array_elements(current_setting('t.intrastat')::jsonb -> 'lines') l),
  '["dispatch:DE", "dispatch:DE"]'::jsonb,
  'a shipment to another member state derives a dispatch line per shipment line'
);
select is(
  (select jsonb_agg(distinct e ->> 'code' order by e ->> 'code') from jsonb_array_elements(current_setting('t.intrastat')::jsonb -> 'exceptions') e),
  '["INTRASTAT_TRADE_CODE_MISSING", "INTRASTAT_VALUE_MISSING"]'::jsonb,
  'lines without a trade code or a value are listed as exceptions'
);
select is(
  jsonb_array_length(better_supabase.prepare_intrastat('00000000-0000-4000-8000-000000000001', current_date) -> 'lines'),
  2,
  'preparing a period again derives the same lines'
);

select * from finish();
rollback;
