-- The reorder quantity, the serial pick and the (id, tenant_id) keys of the
-- inventory block. The admin (…00a1) of Acme (…0001) sets a reorder quantity
-- on a level and picks serial numbers; Globex (…00b1) can do neither.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Drill', 'drill', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'DRILL-1', null, 'Drill', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH7', 'Warehouse 7', null, null) ->> 'id', true);

select is(
  better_supabase.set_reorder_quantity(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 24),
  true,
  'a reorder quantity is stored'
);
select is(
  (select reorder_quantity from better_supabase.stock_levels
   where variant_id = current_setting('t.v')::uuid and location_id = current_setting('t.l')::uuid),
  24::numeric,
  'the level carries it'
);
select throws_ok(
  format($$select better_supabase.set_reorder_quantity(%L, %L, 0)$$, current_setting('t.v'), current_setting('t.l')),
  '22023',
  null,
  'a reorder quantity of zero is refused'
);
select is(
  better_supabase.set_reorder_quantity(current_setting('t.v')::uuid, current_setting('t.l')::uuid, null),
  true,
  'null clears it'
);

select set_config('t.item', (better_supabase.set_stock_item(current_setting('t.v')::uuid, 'pc', 0::smallint, 'serial', true, 'none', null) ->> 'tracking'), true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 1, 'receipt', 'in', '{"serials": ["S-3"]}');
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 2, 'receipt', 'in', '{"serials": ["S-1", "S-2"]}');

select is(
  jsonb_array_length(better_supabase.pick_serials(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 2)),
  2,
  'a pick of two returns two serial numbers'
);
select is(
  better_supabase.pick_serials(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 1),
  '["S-1"]'::jsonb,
  'serials received in one transaction come in serial order'
);
select throws_ok(
  format($$select better_supabase.pick_serials(%L, %L, 4)$$, current_setting('t.v'), current_setting('t.l')),
  '23514',
  null,
  'a pick of more than is in stock is refused'
);

select is(
  (select count(*)::int from pg_constraint c
   where c.contype = 'u'
     and c.conrelid in ('better_supabase.stock_reservations'::regclass, 'better_supabase.inventory_locations'::regclass)
     and (select array_agg(a.attname order by a.attname) from pg_attribute a where a.attrelid = c.conrelid and a.attnum = any (c.conkey)) = array['id', 'tenant_id']::name[]),
  2,
  'reservations and locations are unique by (id, tenant_id)'
);

select * from finish();
rollback;
