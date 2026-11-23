-- Staff order fields and the order list (ADR 1224). The Acme admin (…a1)
-- enters an order with a channel, a source and external id, an order
-- discount, a deposit, a customer party and line units; the same source and
-- external id return the first order. A fractional quantity is refused at the
-- default quantityScale of 0. An order that needs payment ships once its
-- deposit is paid. page_orders filters, searches, facets and counts the
-- organization's orders as the caller. Run with `supabase test db`.
begin;
select plan(18);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Consulting', 'consulting-staff-fields', null, 'service', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'CONSULT-HOUR', null, 'Consulting hour', null, null, false, false, null) ->> 'id', true);

select set_config('t.order', better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
  jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 2, 'unitAmount', '2500',
    'unit', 'h', 'description', 'Workshop prep', 'lineType', 'service')),
  jsonb_build_object('currency', 'EUR', 'channel', 'phone', 'source', 'webshop', 'externalId', 'WS-1001',
    'orderDiscount', '500', 'paymentRequired', true, 'deposit', '1000', 'invoicingPolicy', 'on_delivery',
    'party', jsonb_build_object('type', 'company', 'id', 'c-42')))::text, true);

select is(
  (select jsonb_build_array(o ->> 'channel', o ->> 'source', o ->> 'externalId', o ->> 'invoicingPolicy', o -> 'party')
   from (select current_setting('t.order')::jsonb as o) x),
  '["phone", "webshop", "WS-1001", "on_delivery", {"type": "company", "id": "c-42"}]'::jsonb,
  'the order keeps its channel, source, external id, invoicing policy and party'
);
select is(
  (select jsonb_build_array(o ->> 'subtotal', o ->> 'discountTotal', o ->> 'total', o ->> 'orderDiscount')
   from (select current_setting('t.order')::jsonb as o) x),
  '["5000", "500", "4500", "500"]'::jsonb,
  'the order discount counts in discountTotal and the total'
);
select is(
  (select jsonb_build_array(l ->> 'unit', l ->> 'description', l ->> 'lineType')
   from (select current_setting('t.order')::jsonb -> 'lines' -> 0 as l) x),
  '["h", "Workshop prep", "service"]'::jsonb,
  'a line keeps its unit, description and line type'
);
select is(
  better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    jsonb_build_array(jsonb_build_object('variantId', current_setting('t.v'), 'quantity', 1, 'unitAmount', '2500')),
    jsonb_build_object('currency', 'EUR', 'source', 'webshop', 'externalId', 'WS-1001')) ->> 'id',
  current_setting('t.order')::jsonb ->> 'id',
  'the same source and external id return the first order'
);
select throws_ok(
  $$select better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    '[{"title": "Loose", "quantity": 1, "unitAmount": "100"}]', '{"currency": "EUR", "externalId": "X-1"}')$$,
  '22023',
  'attrs.externalId needs attrs.source, the system the id comes from',
  'an external id needs a source'
);
select throws_ok(
  $$select better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    '[{"title": "Loose", "quantity": 1, "unitAmount": "100"}]', '{"currency": "EUR", "orderDiscount": "101"}')$$,
  '22023',
  'attrs.orderDiscount is more than the lines'' net subtotal',
  'an order discount can''t pass the net subtotal'
);
select throws_ok(
  $$select better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    '[{"title": "Loose", "quantity": 1.5, "unitAmount": "100"}]', '{"currency": "EUR"}')$$,
  '22023',
  'each quantity is a whole number above zero',
  'a fractional quantity is refused at quantityScale 0'
);
select throws_ok(
  $$select better_supabase.order_from_lines('00000000-0000-4000-8000-000000000001',
    '[{"title": "Loose", "quantity": 1, "unitAmount": "100", "lineType": "gift"}]', '{"currency": "EUR"}')$$,
  '22023',
  'a line''s lineType is one of item, service, fee',
  'an unknown line type is refused'
);
select is(
  pg_typeof(quantity)::text,
  'numeric',
  'order line quantities are numeric'
)
from better_supabase.order_lines where order_id = (current_setting('t.order')::jsonb ->> 'id')::uuid;

select throws_ok(
  format($$select better_supabase.create_fulfillment(%L)$$, current_setting('t.order')::jsonb ->> 'id'),
  '55000',
  'the order ships once its deposit, or its total without one, is paid',
  'an order that needs payment doesn''t ship unpaid'
);

reset role;
update better_supabase.orders set paid_total = 1000 where id = (current_setting('t.order')::jsonb ->> 'id')::uuid;
set local role authenticated;

select is(
  better_supabase.create_fulfillment((current_setting('t.order')::jsonb ->> 'id')::uuid) ->> 'status',
  'pending',
  'it ships once the deposit is paid'
);

select is(
  jsonb_array_length(better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"channel": "phone"}')),
  1,
  'page_orders filters by channel'
);
select is(
  better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"search": "ws-10", "paged": true}') -> 'items' -> 0 ->> 'externalId',
  'WS-1001',
  'page_orders searches the external id'
);
select is(
  better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"partyId": "c-42"}') -> 0 -> 'party' ->> 'type',
  'company',
  'page_orders filters by party and returns it'
);
select is(
  jsonb_array_length(better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"source": ["webshop"], "channel": "web"}')),
  0,
  'filters combine'
);
select is(
  better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"facet": "channel", "channel": "phone"}') -> 'values' -> 0 ->> 'value',
  'phone',
  'page_orders facets the channel'
);
select is(
  better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"count": true, "source": "webshop"}') ->> 'value',
  '1',
  'page_orders counts the matching orders'
);

-- Globex's owner sees none of Acme's orders through the list.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.page_orders('00000000-0000-4000-8000-000000000001', '{"source": "webshop"}')),
  0,
  'another organization''s member reads no orders'
);

select * from finish();
rollback;
