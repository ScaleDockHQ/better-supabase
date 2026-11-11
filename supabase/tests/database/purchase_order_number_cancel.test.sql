-- Purchase order numbers and canceled quantities (ADR 0668). The Acme admin
-- (…a1) saves a draft with a number of its own, places a second draft that gets
-- the next number, and can't reuse a number. A placed order gives up part of
-- what it still owes: the units stop counting as incoming, receiving more than
-- is left is refused, and an order with nothing left owed is received, or
-- cancelled when nothing came in. Globex (…b1) can't cancel quantity on an Acme
-- order. Run with `supabase test db`.
begin;
select plan(14);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p1', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Bolt', 'bolt-po-cancel', null, 'physical', null) ->> 'id', true);
select set_config('t.v1', better_supabase.save_variant(current_setting('t.p1')::uuid, null, 'BOLT-1', null, 'Bolt', null, null, true, false, null) ->> 'id', true);
select set_config('t.location', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'POCAN', 'PO cancel dock', null, null) ->> 'id', true);

select set_config('t.po1', better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, current_setting('t.location')::uuid, null, null, 'EUR', null,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v1'), 'quantity', 10, 'unitCost', '100')),
  null, 'PO-100')::text, true);
select is(
  current_setting('t.po1')::jsonb ->> 'number',
  'PO-100',
  'a draft keeps the number it was saved with'
);
select throws_ok(
  format($$select better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, %L, null, null, 'EUR', null,
    '[{"variantId": "%s", "quantity": 1, "unitCost": "100"}]', null, 'PO-100')$$, current_setting('t.location'), current_setting('t.v1')),
  '23505',
  'another purchase order has this number',
  'a number is used once per organization'
);

select set_config('t.po2', better_supabase.save_purchase_order('00000000-0000-4000-8000-000000000001', null, current_setting('t.location')::uuid, null, null, 'EUR', null,
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v1'), 'quantity', 2, 'unitCost', '100')),
  null)::text, true);
select is(
  current_setting('t.po2')::jsonb -> 'number',
  'null'::jsonb,
  'a draft without a number has none yet'
);
select better_supabase.place_purchase_order((current_setting('t.po2')::jsonb ->> 'id')::uuid);
select is(
  (select number from better_supabase.purchase_orders where id = (current_setting('t.po2')::jsonb ->> 'id')::uuid),
  '1',
  'placing an order without a number gives it the next all-digit number'
);
select better_supabase.place_purchase_order((current_setting('t.po1')::jsonb ->> 'id')::uuid);
select is(
  (select number from better_supabase.purchase_orders where id = (current_setting('t.po1')::jsonb ->> 'id')::uuid),
  'PO-100',
  'placing an order keeps its own number'
);

-- Canceled quantity on the placed order of ten units.
select set_config('t.line', (select id::text from better_supabase.purchase_order_lines where purchase_order_id = (current_setting('t.po1')::jsonb ->> 'id')::uuid), true);
select is(
  (select incoming from better_supabase.stock_levels where variant_id = current_setting('t.v1')::uuid and location_id = current_setting('t.location')::uuid),
  12::numeric,
  'both placed orders count as incoming'
);
select is(
  better_supabase.cancel_purchase_order_quantity((current_setting('t.po1')::jsonb ->> 'id')::uuid,
    jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'quantity', 4))),
  '{"status": "ordered", "backordered": 6}'::jsonb,
  'giving up four of ten units leaves six owed'
);
select is(
  (select incoming from better_supabase.stock_levels where variant_id = current_setting('t.v1')::uuid and location_id = current_setting('t.location')::uuid),
  8::numeric,
  'the canceled units stop counting as incoming'
);
select throws_ok(
  format($$select better_supabase.cancel_purchase_order_quantity(%L, '[{"lineId": "%s", "quantity": 7}]')$$, current_setting('t.po1')::jsonb ->> 'id', current_setting('t.line')),
  '22023',
  'a line would cancel more than it still owes',
  'a line can''t give up more than it still owes'
);
select throws_ok(
  format($$select better_supabase.receive_purchase_order(%L, '[{"lineId": "%s", "quantity": 7}]')$$, current_setting('t.po1')::jsonb ->> 'id', current_setting('t.line')),
  '22023',
  'a line would receive more than was ordered',
  'receiving more than is left after the cancellation is refused'
);
select is(
  (better_supabase.receive_purchase_order((current_setting('t.po1')::jsonb ->> 'id')::uuid,
    jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'quantity', 2))) ->> 'backordered')::numeric,
  4::numeric,
  'a receipt counts what is left after the cancellation'
);
select is(
  better_supabase.cancel_purchase_order_quantity((current_setting('t.po1')::jsonb ->> 'id')::uuid,
    jsonb_build_array(jsonb_build_object('lineId', current_setting('t.line'), 'quantity', 4))) ->> 'status',
  'received',
  'an order with nothing left owed is received once something came in'
);
select is(
  better_supabase.cancel_purchase_order_quantity((current_setting('t.po2')::jsonb ->> 'id')::uuid,
    jsonb_build_array(jsonb_build_object('lineId', (select id::text from better_supabase.purchase_order_lines where purchase_order_id = (current_setting('t.po2')::jsonb ->> 'id')::uuid), 'quantity', 2))) ->> 'status',
  'cancelled',
  'an order that gave up everything is cancelled when nothing came in'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  format($$select better_supabase.cancel_purchase_order_quantity(%L, '[{"lineId": "%s", "quantity": 1}]')$$, current_setting('t.po1')::jsonb ->> 'id', current_setting('t.line')),
  null,
  null,
  'another organization can''t cancel quantity on the order'
);

select * from finish();
rollback;
