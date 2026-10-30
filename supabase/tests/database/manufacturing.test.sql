-- The manufacturing module against the seed (ADR 0139). The Acme owner (…a1)
-- makes bread from flour (kilograms in lots) and salt (grams) in an oven work
-- center: a bill of materials with one operation, a production order that
-- allocates, consumes and receives stock through the inventory ledger, and the
-- lot genealogy that links the bread's lot to the flour's. The member (…a2)
-- reads and produces but can't change bills of materials, and the Globex owner
-- (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(31);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('boms', 'bom_components', 'work_centers', 'bom_operations', 'production_orders',
       'production_order_operations', 'production_consumptions', 'stock_lot_links')
     and rowsecurity),
  8::bigint,
  'the manufacturing tables have RLS enabled'
);
select table_privs_are('better_supabase', 'production_orders', 'anon', '{}'::text[],
  'anon has no privileges on production orders');
select table_privs_are('better_supabase', 'production_orders', 'authenticated', array['SELECT'],
  'authenticated only reads production orders; writes go through the functions');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids
select v.name, (better_supabase.save_variant(
  (better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, v.title, v.name, null, 'physical', null) ->> 'id')::uuid,
  null, upper(v.name), null, v.title, null, null, true, false, null) ->> 'id')::uuid
from (values ('bread', 'Bread'), ('flour', 'Flour'), ('salt', 'Salt')) v(name, title);
insert into ids values ('bakery', (better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'BAK', 'Bakery', null, null) ->> 'id')::uuid);
select better_supabase.set_stock_item((select id from ids where name = 'bread'), 'pcs', 0::smallint, 'lot', false, 'average', 'EUR');
select better_supabase.set_stock_item((select id from ids where name = 'flour'), 'kg', 3::smallint, 'lot', false, 'average', 'EUR');
select better_supabase.set_stock_item((select id from ids where name = 'salt'), 'g', 0::smallint, 'none', false, 'average', 'EUR');
select better_supabase.adjust_stock((select id from ids where name = 'flour'), (select id from ids where name = 'bakery'), 10, 'receipt', null,
  '{"lot": {"code": "F1"}, "unitCost": "200", "currency": "EUR"}');
select better_supabase.adjust_stock((select id from ids where name = 'salt'), (select id from ids where name = 'bakery'), 100, 'receipt', null,
  '{"unitCost": "10", "currency": "EUR"}');
insert into ids values ('flour_lot', (select x.id from better_supabase.stock_lots x where x.variant_id = (select id from ids where name = 'flour') and x.code = 'F1'));

insert into ids values ('oven', (better_supabase.save_work_center('00000000-0000-4000-8000-000000000001',
  '{"name": "Oven", "costRate": 6000, "currency": "EUR"}') ->> 'id')::uuid);
select is(
  (select jsonb_build_array(x ->> 'name', x ->> 'costRate', x ->> 'currency')
   from jsonb_array_elements(better_supabase.list_work_centers('00000000-0000-4000-8000-000000000001')) x),
  '["Oven", "6000", "EUR"]'::jsonb,
  'the owner adds a work center at 60.00 EUR an hour'
);

insert into ids values ('bread_bom', (better_supabase.save_bom('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'bread'),
  jsonb_build_object(
    'operations', jsonb_build_array(jsonb_build_object('sequence', 10, 'workCenterId', (select id from ids where name = 'oven'),
      'title', 'Bake', 'runMinutesPerUnit', 6)),
    'components', jsonb_build_array(
      jsonb_build_object('variantId', (select id from ids where name = 'flour'), 'quantity', 0.5, 'operation', 10),
      jsonb_build_object('variantId', (select id from ids where name = 'salt'), 'quantity', 10))
  )) ->> 'id')::uuid);
select is(
  (select jsonb_build_array(status, version) from better_supabase.boms where id = (select id from ids where name = 'bread_bom')),
  '["draft", 1]'::jsonb,
  'a new bill of materials is draft version 1'
);
select throws_ok(
  format($$select better_supabase.save_bom('00000000-0000-4000-8000-000000000001', %L, jsonb_build_object('components', jsonb_build_array(jsonb_build_object('variantId', %L, 'quantity', 1))))$$,
    (select id from ids where name = 'bread'), (select id from ids where name = 'bread')),
  '22023',
  'a variant can''t be a component of itself',
  'a variant is refused as its own component'
);
select throws_ok(
  format($$select better_supabase.create_production_order('00000000-0000-4000-8000-000000000001', jsonb_build_object('variantId', %L, 'quantity', 1))$$,
    (select id from ids where name = 'bread')),
  '55000',
  'the variant has no active bill of materials',
  'a production order needs an active bill of materials'
);
select is(
  better_supabase.activate_bom((select id from ids where name = 'bread_bom')) ->> 'status',
  'active',
  'the owner activates the bill of materials'
);

insert into ids values ('flour_bom', (better_supabase.save_bom('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'flour'),
  jsonb_build_object('components', jsonb_build_array(jsonb_build_object('variantId', (select id from ids where name = 'bread'), 'quantity', 1)))) ->> 'id')::uuid);
select throws_ok(
  format($$select better_supabase.activate_bom(%L)$$, (select id from ids where name = 'flour_bom')),
  '22023',
  'a component is made from the variant itself',
  'a bill of materials that closes a cycle does not activate'
);

select is(
  (select jsonb_agg(m ->> 'quantity' order by m ->> 'quantity')
   from jsonb_array_elements(better_supabase.explode_bom((select id from ids where name = 'bread'), 4) -> 'materials') m),
  '["2.000", "40"]'::jsonb,
  'four breads take 2 kg of flour and 40 g of salt'
);
select is(
  (select jsonb_agg(u ->> 'variantId') from jsonb_array_elements(better_supabase.bom_where_used((select id from ids where name = 'flour'))) u),
  jsonb_build_array((select id from ids where name = 'bread')),
  'flour is used in bread'
);

insert into ids values ('order', (better_supabase.create_production_order('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('variantId', (select id from ids where name = 'bread'), 'quantity', 4)) ->> 'id')::uuid);
select matches(
  (select number from better_supabase.production_orders where id = (select id from ids where name = 'order')),
  '^MO-\d{4}-0001$',
  'the order takes its number from the numbering block'
);
select is(
  better_supabase.release_production_order((select id from ids where name = 'order')) ->> 'status',
  'released',
  'the owner releases the order'
);
select is(
  (select jsonb_agg(c ->> 'allocated' order by c ->> 'allocated')
   from jsonb_array_elements(better_supabase.get_production_order((select id from ids where name = 'order')) -> 'components') c),
  '["2.000000", "40.000000"]'::jsonb,
  'release allocates each component at the order''s location'
);
select is(
  (select jsonb_build_array(sequence, planned_minutes::text, status) from better_supabase.production_order_operations
   where order_id = (select id from ids where name = 'order')),
  '[10, "24.00", "pending"]'::jsonb,
  'release copies the operation with its planned minutes'
);

insert into ids values ('big', (better_supabase.create_production_order('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('variantId', (select id from ids where name = 'bread'), 'quantity', 100)) ->> 'id')::uuid);
select throws_ok(
  format($$select better_supabase.release_production_order(%L)$$, (select id from ids where name = 'big')),
  '23514',
  'not enough stock for the production order''s components',
  'a release that would backorder a component is refused'
);
select ok(
  exists (select 1 from jsonb_array_elements(better_supabase.material_requirements('00000000-0000-4000-8000-000000000001') -> 'items') i
    where i ->> 'variantId' = (select id from ids where name = 'flour')::text and i ->> 'action' = 'purchase'),
  'the draft order makes flour a purchase requirement'
);
select is(
  better_supabase.cancel_production_order((select id from ids where name = 'big'), 'Too large') ->> 'status',
  'canceled',
  'a draft order cancels'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select better_supabase.save_bom('00000000-0000-4000-8000-000000000001', %L, jsonb_build_object('components', jsonb_build_array(jsonb_build_object('variantId', %L, 'quantity', 1))))$$,
    (select id from ids where name = 'bread'), (select id from ids where name = 'salt')),
  '42501',
  null,
  'a member cannot change bills of materials'
);
select is(
  better_supabase.start_production_operation((select id from better_supabase.production_order_operations
    where order_id = (select id from ids where name = 'order'))) ->> 'status',
  'in_progress',
  'a member starts the operation'
);
select is(
  (select status from better_supabase.production_orders where id = (select id from ids where name = 'order')),
  'in_progress',
  'starting an operation starts the order'
);
insert into ids values ('done', (better_supabase.complete_production_order((select id from ids where name = 'order'), 4) ->> 'outputLotId')::uuid);
select is(
  (select jsonb_build_array(status, produced_quantity::text, material_cost, labor_cost, currency)
   from better_supabase.production_orders where id = (select id from ids where name = 'order')),
  '["done", "4.000000", 800, 2400, "EUR"]'::jsonb,
  'a member completes the order at 8.00 EUR of material and 24.00 EUR of labor'
);
select is(
  (select code from better_supabase.stock_lots where id = (select id from ids where name = 'done')),
  (select number from better_supabase.production_orders where id = (select id from ids where name = 'order')),
  'the bread lands in a lot named after the order'
);
select is(
  (select jsonb_build_array(on_hand::text, available::text) from better_supabase.stock_levels
   where variant_id = (select id from ids where name = 'flour') and location_id = (select id from ids where name = 'bakery')),
  '["8.000000", "8.000000"]'::jsonb,
  'the flour is consumed and its allocation released'
);
select is(
  (select on_hand::text from better_supabase.stock_levels
   where variant_id = (select id from ids where name = 'bread') and location_id = (select id from ids where name = 'bakery')),
  '4.000000',
  'four breads are on hand'
);
select is(
  (select jsonb_agg(l ->> 'code') from jsonb_array_elements(better_supabase.lot_genealogy((select id from ids where name = 'done'), 'down') -> 'lots') l),
  '["F1"]'::jsonb,
  'the bread lot was made from flour lot F1'
);
select is(
  (select jsonb_agg(l ->> 'lotId') from jsonb_array_elements(better_supabase.lot_genealogy((select id from ids where name = 'flour_lot'), 'up') -> 'lots') l),
  jsonb_build_array((select id from ids where name = 'done')),
  'flour lot F1 went into the bread lot'
);
select is(
  (select jsonb_build_array(jsonb_array_length(r -> 'lots'), jsonb_array_length(r -> 'orders'))
   from (select better_supabase.lot_recall((select id from ids where name = 'flour_lot')) r) x),
  '[2, 1]'::jsonb,
  'a recall of F1 reaches the bread lot and the order that consumed it'
);
select throws_ok(
  format($$select better_supabase.cancel_production_order(%L)$$, (select id from ids where name = 'order')),
  '42501',
  null,
  'a member cannot cancel production orders'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.boms) + (select count(*) from better_supabase.production_orders)
    + (select count(*) from better_supabase.stock_lot_links),
  0::bigint,
  'the Globex owner sees no Acme bills of materials, orders or lot links'
);
select throws_ok(
  format($$select better_supabase.get_production_order(%L)$$, (select id from ids where name = 'order')),
  'P0002',
  null,
  'the Globex owner cannot read an Acme production order'
);
select * from finish();
rollback;
