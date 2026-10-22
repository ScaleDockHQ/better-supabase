-- The orders kitchen on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) routes a product to the grill, sends an order to the kitchen,
-- moves its lines through queued, preparing, ready and served, and every
-- change pings the kitchen topic. Someone outside Acme (…00e2) can't move a
-- line.
begin;
select plan(13);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e2', 'someone@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

insert into better_supabase.products (id, tenant_id, slug, title) values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'burger', 'Burger'),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', 'salad', 'Salad');
insert into better_supabase.orders (id, tenant_id, number, sequence, currency, status) values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-000000000001', 'K-1', 1, 'EUR', 'paid'),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-000000000001', 'K-2', 2, 'EUR', 'cancelled');
insert into better_supabase.order_lines (id, tenant_id, order_id, position, product_id, sku, title, quantity) values
  ('00000000-0000-4000-8000-00000000f201', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', 1, '00000000-0000-4000-8000-00000000f001', 'BRG', 'Burger', 2),
  ('00000000-0000-4000-8000-00000000f202', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f101', 2, '00000000-0000-4000-8000-00000000f002', 'SLD', 'Salad', 1);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.grill', better_supabase.save_kitchen_station(
  '00000000-0000-4000-8000-000000000001', null,
  '{"key": "grill", "name": "Grill", "productIds": ["00000000-0000-4000-8000-00000000f001"]}'
)::text, true);
select set_config('test.cold', better_supabase.save_kitchen_station(
  '00000000-0000-4000-8000-000000000001', null, '{"key": "cold", "name": "Cold", "default": true}'
)::text, true);

select is(
  current_setting('test.grill')::jsonb -> 'productIds',
  '["00000000-0000-4000-8000-00000000f001"]'::jsonb,
  'a station keeps the products routed to it'
);
select is(
  better_supabase.send_order_to_kitchen('00000000-0000-4000-8000-00000000f101', '{"00000000-0000-4000-8000-00000000f201": "No onions"}'),
  2,
  'sending an order queues each of its lines'
);
select is(
  better_supabase.send_order_to_kitchen('00000000-0000-4000-8000-00000000f101', null),
  0,
  'sending it again queues nothing new'
);
select is(
  (select station_id from better_supabase.order_line_preparations where order_line_id = '00000000-0000-4000-8000-00000000f201'),
  (current_setting('test.grill')::jsonb ->> 'id')::uuid,
  'a routed product goes to its station'
);
select is(
  (select station_id from better_supabase.order_line_preparations where order_line_id = '00000000-0000-4000-8000-00000000f202'),
  (current_setting('test.cold')::jsonb ->> 'id')::uuid,
  'an unrouted product goes to the default station'
);
select throws_ok(
  $$select better_supabase.send_order_to_kitchen('00000000-0000-4000-8000-00000000f102', null)$$,
  '22023',
  null,
  'a cancelled order does not go to the kitchen'
);
select is(
  better_supabase.set_line_preparation('00000000-0000-4000-8000-00000000f201', 'preparing') ->> 'state',
  'preparing',
  'a cook starts a line'
);
select throws_ok(
  $$select better_supabase.set_line_preparation('00000000-0000-4000-8000-00000000f201', 'burnt')$$,
  '22023',
  null,
  'an unknown state is refused'
);
select is(
  better_supabase.bump_kitchen_ticket('00000000-0000-4000-8000-00000000f101', null, 'ready'),
  2,
  'bumping a ticket moves every line behind it'
);
select is(
  jsonb_array_length(better_supabase.kitchen_queue('00000000-0000-4000-8000-000000000001', null, array['queued', 'preparing'], null)),
  0,
  'a ready ticket leaves the queue of open work'
);

reset role;
select is(
  (select count(*) from better_supabase.outbox_events where type = 'order.prepared'),
  1::bigint,
  'every line ready records order.prepared'
);
select ok(
  (select count(*) from realtime.messages where topic = 'kitchen:00000000-0000-4000-8000-000000000001') >= 4,
  'every change pings the kitchen topic'
);

-- Someone outside Acme.
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000e2","role":"authenticated"}', true);
set local role authenticated;

select throws_ok(
  $$select better_supabase.set_line_preparation('00000000-0000-4000-8000-00000000f202', 'served')$$,
  '42501',
  null,
  'an outsider cannot move a line'
);

select * from finish();
rollback;
