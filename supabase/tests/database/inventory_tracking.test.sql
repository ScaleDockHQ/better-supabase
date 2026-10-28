-- Fractional stock, lots, bins, average cost, allocations, document orders
-- and shipment lines on the fixture's access contract (ADR 0126). The admin
-- (…00a1) of Acme (…0001) sells flour by the kilogram at scale 3 in lots,
-- orders it from lines and from an accepted quote, and ships it with
-- shipment lines that take the stock out and receive a return. Globex
-- (…00b1) sees none of it.
begin;
select plan(24);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Flour', 'flour', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'FLOUR-KG', null, 'Flour', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH1', 'Warehouse', null, null) ->> 'id', true);

select is(
  (select jsonb_build_array(x ->> 'unit', x ->> 'scale', x ->> 'tracking', x ->> 'costing')
   from better_supabase.set_stock_item(current_setting('t.v')::uuid, 'kg', 3::smallint, 'lot', true, 'average', 'EUR') x),
  '["kg", "3", "lot", "average"]'::jsonb,
  'a variant is tracked by the kilogram at scale 3, in lots, at average cost'
);
select set_config('t.hold', better_supabase.save_bin(current_setting('t.l')::uuid, null, 'HOLD', 'Quarantine', true, true) ->> 'id', true);

select is(
  (better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 10.5, 'receipt', 'in',
    '{"lot": {"code": "L1", "expiresOn": "2030-02-01"}, "unitCost": "200", "currency": "EUR"}') ->> 'onHand')::numeric,
  10.5,
  'a receipt of 10.5 kg lands in lot L1'
);
select throws_ok(
  format($$select better_supabase.adjust_stock(%L, %L, 1.2345, 'receipt', null, '{"lot": {"code": "L1"}}')$$, current_setting('t.v'), current_setting('t.l')),
  '22023',
  null,
  'a quantity finer than the scale is refused'
);
select throws_ok(
  format($$select better_supabase.adjust_stock(%L, %L, 1, 'receipt', null)$$, current_setting('t.v'), current_setting('t.l')),
  '22023',
  null,
  'stock tracked in lots needs a lot'
);
select is(
  (select jsonb_build_array(d ->> 'onHand', d -> 'buckets' -> 0 ->> 'lotCode', d -> 'buckets' -> 0 ->> 'expiresOn')
   from better_supabase.stock_detail(current_setting('t.v')::uuid, current_setting('t.l')::uuid) d),
  '["10.500000", "L1", "2030-02-01"]'::jsonb,
  'the detail shows the lot bucket and its expiry'
);
select is(
  (select jsonb_build_array(x ->> 'averageCost', x ->> 'value') from better_supabase.stock_valuation(current_setting('t.v')::uuid) x),
  '["200.000000", "2100"]'::jsonb,
  'the stock is valued at its average cost'
);
select is(
  jsonb_array_length(better_supabase.expiring_lots('00000000-0000-4000-8000-000000000001', '2030-03-01')),
  1,
  'the lot expires before March'
);

select set_config('t.alloc', better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 12, 'work_order', 'w1', 'l1', true)::text, true);
select is(
  (select jsonb_build_array(a ->> 'allocated', a ->> 'backordered') from (select current_setting('t.alloc')::jsonb a) x),
  '["10.500000", "1.500000"]'::jsonb,
  'an allocation takes what is there and backorders the rest'
);
select throws_ok(
  format($$select better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', %L, %L, 1, 'work_order', 'w2', null, false)$$, current_setting('t.v'), current_setting('t.l')),
  '23514',
  'not enough stock available',
  'without backorder an allocation needs available stock'
);
select is(
  better_supabase.release_allocations('00000000-0000-4000-8000-000000000001', 'work_order', 'w1'),
  1,
  'releasing the document frees its allocation'
);

select set_config('t.order', better_supabase.order_from_lines(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '500')),
  jsonb_build_object('currency', 'EUR', 'locationId', current_setting('t.l'), 'origin', jsonb_build_object('type', 'phone', 'id', 'call-1'))
)::text, true);
select is(
  (select jsonb_build_array(o ->> 'status', o ->> 'total', o ->> 'created') from (select current_setting('t.order')::jsonb o) x),
  '["confirmed", "1000", "true"]'::jsonb,
  'an order from lines starts confirmed with its total'
);
select is(
  (select jsonb_agg(a ->> 'allocated') from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', current_setting('t.order')::jsonb ->> 'id')) a),
  '["2.000000"]'::jsonb,
  'its line holds its stock as an allocation'
);
select is(
  better_supabase.order_from_lines(
    '00000000-0000-4000-8000-000000000001',
    jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '500')),
    jsonb_build_object('currency', 'EUR', 'origin', jsonb_build_object('type', 'phone', 'id', 'call-1'))
  ) ->> 'id',
  current_setting('t.order')::jsonb ->> 'id',
  'an origin orders once'
);

select set_config('t.q', better_supabase.create_quote(
  '00000000-0000-4000-8000-000000000001',
  '{"title": "Bulk", "currency": "EUR"}',
  jsonb_build_array(jsonb_build_object('description', 'Flour', 'quantity', 3, 'unitAmount', '450', 'product', jsonb_build_object('type', 'product_variant', 'id', current_setting('t.v'))))
) ->> 'id', true);
select throws_ok(
  format($$select better_supabase.order_from_quote(%L)$$, current_setting('t.q')),
  '55000',
  'only an accepted quote becomes an order',
  'a draft quote does not order'
);
select better_supabase.send_quote(current_setting('t.q')::uuid);
select better_supabase.decide_quote(current_setting('t.q')::uuid, 'accepted', null, null, null);
select set_config('t.qo', better_supabase.order_from_quote(current_setting('t.q')::uuid, jsonb_build_object('locationId', current_setting('t.l')))::text, true);
select is(
  (select jsonb_build_array(o ->> 'status', o ->> 'total', o -> 'lines' -> 0 ->> 'variantId') from (select current_setting('t.qo')::jsonb o) x),
  jsonb_build_array('confirmed', '1350', current_setting('t.v')),
  'an accepted quote orders its variant lines at the quote total'
);
select is(
  better_supabase.order_from_quote(current_setting('t.q')::uuid) ->> 'created',
  'false',
  'a quote orders once'
);
select better_supabase.cancel_order((current_setting('t.qo')::jsonb ->> 'id')::uuid, 'changed');
select is(
  (select jsonb_agg(a ->> 'status') from jsonb_array_elements(better_supabase.list_allocations('00000000-0000-4000-8000-000000000001', 'order', current_setting('t.qo')::jsonb ->> 'id')) a),
  '["released"]'::jsonb,
  'cancelling the order releases its allocation'
);

select set_config('t.s', better_supabase.create_shipment('00000000-0000-4000-8000-000000000001',
  '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[{"weightGrams": 1000}]') ->> 'id', true);
select better_supabase.set_shipment_lines(current_setting('t.s')::uuid,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.l'), 'quantity', '1.25')));
select is(
  (select jsonb_build_array(l ->> 'quantity', l -> 'detail' -> 'parts' -> 0 ->> 'quantity')
   from (select better_supabase.set_shipment_label(current_setting('t.s')::uuid, 'flat-rate', 'standard', 'FRX', 'lbl_x', 695, 'EUR') -> 'lines' -> 0 l) x),
  '["1.250000", "1.250000"]'::jsonb,
  'the label takes the line''s stock out and records the lot it came from'
);
select is(
  better_supabase.stock_detail(current_setting('t.v')::uuid, current_setting('t.l')::uuid) ->> 'onHand',
  '9.250000',
  'the stock left the warehouse'
);
select throws_ok(
  format($$select better_supabase.receive_shipment_return(%L, %L)$$, current_setting('t.s'),
    jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.l'), 'quantity', '2', 'disposition', 'restock', 'detail', '{"lot": {"code": "L1"}}'::jsonb))),
  '22023',
  'a variant comes back at most as often as the shipment carried it out',
  'a return is at most what shipped'
);
select is(
  jsonb_array_length(better_supabase.receive_shipment_return(current_setting('t.s')::uuid, jsonb_build_array(
    jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.l'), 'quantity', '0.5', 'disposition', 'hold', 'detail', jsonb_build_object('binId', current_setting('t.hold'), 'lot', '{"code": "L1"}'::jsonb)),
    jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.l'), 'quantity', '0.25', 'disposition', 'scrap', 'detail', '{"lot": {"code": "L1"}}'::jsonb)
  )) -> 'lines'),
  3,
  'a return records one line per disposition'
);
select is(
  (select jsonb_build_array(d ->> 'onHand', d ->> 'held') from better_supabase.stock_detail(current_setting('t.v')::uuid, current_setting('t.l')::uuid) d),
  '["9.750000", "0.500000"]'::jsonb,
  'the held return sits in the hold bin and the scrapped part is written off'
);

select set_config('t.s2', better_supabase.create_shipment('00000000-0000-4000-8000-000000000001',
  '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[{"weightGrams": 1000}]') ->> 'id', true);
select better_supabase.set_shipment_lines(current_setting('t.s2')::uuid,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'locationId', current_setting('t.l'), 'quantity', '1')));
select better_supabase.set_shipment_label(current_setting('t.s2')::uuid, 'flat-rate', 'standard', 'FRY', 'lbl_y', 695, 'EUR');
select better_supabase.cancel_shipment(current_setting('t.s2')::uuid);
select is(
  better_supabase.stock_detail(current_setting('t.v')::uuid, current_setting('t.l')::uuid) ->> 'onHand',
  '9.750000',
  'cancelling a labeled shipment puts its stock back'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*)::int from better_supabase.stock_allocations) + (select count(*)::int from better_supabase.shipment_lines) + (select count(*)::int from better_supabase.stock_lots),
  0,
  'another organization sees no allocations, shipment lines or lots'
);

select * from finish();
rollback;
