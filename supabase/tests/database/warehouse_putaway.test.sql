-- Putaway, slotting and pick routes (ADR 0179). The Acme admin (…a1) sets up
-- bins with walk ranks and capacities, a rule for one variant and a variant
-- size, asks where a receipt's stock goes, picks stock in a far bin and asks
-- where it should live, orders a pick list and completes it so that its work
-- item is done. The Acme member (…a2) can read suggestions but not manage
-- rules, and the Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(16);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('putaway_rules', 'bin_slots', 'variant_sizes')
     and rowsecurity),
  3::bigint,
  'the putaway tables have RLS enabled'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Putaway bolts', 'putaway-bolts', null, 'physical', null) ->> 'id', true);
select set_config('t.v1', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'PUT-1', null, 'Bolts', null, null, true, false, null) ->> 'id', true);
select set_config('t.product2', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Putaway nuts', 'putaway-nuts', null, 'physical', null) ->> 'id', true);
select set_config('t.v2', better_supabase.save_variant(current_setting('t.product2')::uuid, null, 'PUT-2', null, 'Nuts', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'PUT', 'Putaway warehouse', null, null) ->> 'id', true);
select set_config('t.a', better_supabase.save_bin(current_setting('t.l')::uuid, null, 'A1', 'Near', false, true) ->> 'id', true);
select set_config('t.b', better_supabase.save_bin(current_setting('t.l')::uuid, null, 'B1', 'Middle', false, true) ->> 'id', true);
select set_config('t.c', better_supabase.save_bin(current_setting('t.l')::uuid, null, 'C1', 'Far', false, true) ->> 'id', true);
select set_config('t.h', better_supabase.save_bin(current_setting('t.l')::uuid, null, 'H1', 'Quarantine', true, true) ->> 'id', true);

select better_supabase.save_bin_slot('00000000-0000-4000-8000-000000000001', jsonb_build_object('binId', current_setting('t.a'), 'walkRank', 1, 'capacity', 10));
select better_supabase.save_bin_slot('00000000-0000-4000-8000-000000000001', jsonb_build_object('binId', current_setting('t.b'), 'walkRank', 2, 'capacity', 100));
select better_supabase.save_bin_slot('00000000-0000-4000-8000-000000000001', jsonb_build_object('binId', current_setting('t.c'), 'walkRank', 3));
select better_supabase.save_bin_slot('00000000-0000-4000-8000-000000000001', jsonb_build_object('binId', current_setting('t.h'), 'walkRank', 0));
select better_supabase.save_variant_size('00000000-0000-4000-8000-000000000001', jsonb_build_object('variantId', current_setting('t.v1'), 'size', 2));
select set_config('t.rule', better_supabase.save_putaway_rule('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('locationId', current_setting('t.l'), 'binId', current_setting('t.b'), 'variantId', current_setting('t.v1'), 'priority', 10, 'maxQuantity', 20)) ->> 'id', true);

select is(
  (select jsonb_agg(jsonb_build_array(x ->> 'code', x ->> 'walkRank', x ->> 'capacity') order by x ->> 'code')
   from jsonb_array_elements(better_supabase.list_bin_slots('00000000-0000-4000-8000-000000000001', jsonb_build_object('locationId', current_setting('t.l')))) x),
  '[["A1", "1", "10.000000"], ["B1", "2", "100.000000"], ["C1", "3", null], ["H1", "0", null]]'::jsonb,
  'the bins list with their slots'
);

select is(
  (select jsonb_agg(jsonb_build_array(p.v ->> 'binCode', p.v ->> 'quantity', p.v ->> 'source') order by p.n)
   from jsonb_array_elements(better_supabase.suggest_putaway('00000000-0000-4000-8000-000000000001',
     jsonb_build_object('locationId', current_setting('t.l'), 'variantId', current_setting('t.v1'), 'quantity', 30)) -> 'placements') with ordinality as p(v, n)),
  '[["B1", "20.000000", "rule"], ["A1", "5.000000", "free"], ["C1", "5.000000", "free"]]'::jsonb,
  'the rule bin comes first up to its limit, then free bins by walk rank within their capacity, skipping the hold bin'
);
select is(
  better_supabase.suggest_putaway('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('locationId', current_setting('t.l'), 'variantId', current_setting('t.v1'), 'quantity', 30)) ->> 'unassigned',
  '0.000000',
  'nothing is left over when the bins have room'
);

select better_supabase.adjust_stock(current_setting('t.v1')::uuid, current_setting('t.l')::uuid, 4, 'receipt', null,
  jsonb_build_object('binId', current_setting('t.c')));
select is(
  (select p ->> 'binCode'
   from jsonb_array_elements(better_supabase.suggest_putaway('00000000-0000-4000-8000-000000000001',
     jsonb_build_object('locationId', current_setting('t.l'), 'variantId', current_setting('t.v1'), 'quantity', 1)) -> 'placements') p
   limit 1),
  'B1',
  'a rule beats a bin that already holds the variant'
);
select is(
  (select jsonb_agg(p.v ->> 'binCode' order by p.n)
   from jsonb_array_elements(better_supabase.suggest_putaway('00000000-0000-4000-8000-000000000001',
     jsonb_build_object('locationId', current_setting('t.l'), 'variantId', current_setting('t.v2'), 'quantity', 3)) -> 'placements') with ordinality as p(v, n)),
  '["A1"]'::jsonb,
  'a variant without rules goes to the closest bin with room'
);
select throws_ok(
  format($$select better_supabase.save_putaway_rule('00000000-0000-4000-8000-000000000001', jsonb_build_object('locationId', %L, 'binId', %L, 'maxQuantity', 0))$$,
    current_setting('t.l'), current_setting('t.a')),
  '22023',
  null,
  'a rule limit is more than zero'
);
select is(
  better_supabase.delete_putaway_rule(current_setting('t.rule')::uuid),
  true,
  'a rule is deleted'
);
select is(
  better_supabase.delete_putaway_rule(current_setting('t.rule')::uuid),
  false,
  'deleting a rule that is gone says so'
);

reset role;
set local session_replication_role = replica;
with r as (
  insert into better_supabase.inventory_receipts (tenant_id, purchase_order_id, location_id)
  values ('00000000-0000-4000-8000-000000000001', gen_random_uuid(), current_setting('t.l')::uuid) returning id)
select set_config('t.receipt', id::text, true) from r;
insert into better_supabase.inventory_receipt_lines (tenant_id, receipt_id, purchase_order_line_id, variant_id, quantity, unit_cost)
values ('00000000-0000-4000-8000-000000000001', current_setting('t.receipt')::uuid, gen_random_uuid(), current_setting('t.v2')::uuid, 2, 0),
       ('00000000-0000-4000-8000-000000000001', current_setting('t.receipt')::uuid, gen_random_uuid(), current_setting('t.v2')::uuid, 1, 0);
set local session_replication_role = origin;
set local role authenticated;
select is(
  (select jsonb_build_array(jsonb_array_length(x), x -> 0 ->> 'quantity', x -> 0 -> 'placements' -> 0 ->> 'binCode')
   from (select better_supabase.suggest_receipt_putaway(current_setting('t.receipt')::uuid) x) y),
  '[1, "3.000000", "A1"]'::jsonb,
  'a receipt''s lines of one variant are planned together'
);

select better_supabase.adjust_stock(current_setting('t.v2')::uuid, current_setting('t.l')::uuid, 8, 'receipt', null,
  jsonb_build_object('binId', current_setting('t.c')));
select better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v2')::uuid, current_setting('t.l')::uuid, 5, 'work_order', 'p1', 'l1', true);
select better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v1')::uuid, current_setting('t.l')::uuid, 2, 'work_order', 'p1', 'l2', true);

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('list', (better_supabase.create_pick_list(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('locationId', current_setting('t.l'), 'documentType', 'work_order', 'documentId', 'p1')) ->> 'id')::uuid);
select set_config('t.lines', (
  select jsonb_agg(l ->> 'id' order by (l ->> 'variantId' = current_setting('t.v2')) desc)::text
  from jsonb_array_elements(better_supabase.get_pick_list((select id from ids where name = 'list')) -> 'lines') l), true);

select is(
  (select jsonb_agg(l.v ->> 'id' order by l.n)
   from jsonb_array_elements(better_supabase.set_pick_route((select id from ids where name = 'list'),
     array(select jsonb_array_elements_text(current_setting('t.lines')::jsonb)::uuid)) -> 'lines') with ordinality as l(v, n)),
  current_setting('t.lines')::jsonb,
  'the lines follow the route that was set'
);
select throws_ok(
  format($$select better_supabase.set_pick_route(%L, array[gen_random_uuid()])$$, (select id from ids where name = 'list')),
  '22023',
  null,
  'a route lists lines of the pick list'
);

select better_supabase.record_pick((current_setting('t.lines')::jsonb ->> 0)::uuid, jsonb_build_object('quantity', 5));
select better_supabase.record_pick((current_setting('t.lines')::jsonb ->> 1)::uuid, jsonb_build_object('quantity', 2));

select is(
  (select jsonb_build_array(x.v ->> 'variantId' = current_setting('t.v2'), x.v ->> 'velocity', x.v ->> 'suggestedBinId' = current_setting('t.a'), x.v ->> 'action')
   from jsonb_array_elements(better_supabase.suggest_slotting('00000000-0000-4000-8000-000000000001', jsonb_build_object('locationId', current_setting('t.l'))))
     with ordinality as x(v, n)
   where x.n = 1),
  '[true, "5.000000", true, "move"]'::jsonb,
  'the fastest variant is suggested the closest bin with room, and it moves'
);

select set_config('t.task', better_supabase.complete_pick_list((select id from ids where name = 'list')) ->> 'taskId', true);
select is(
  (select t.state from better_supabase.work_items t where t.id = current_setting('t.task')::uuid),
  'completed',
  'completing the pick list moves the picker''s work item to done'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.save_putaway_rule('00000000-0000-4000-8000-000000000001', jsonb_build_object('locationId', %L, 'binId', %L))$$,
    current_setting('t.l'), current_setting('t.a')),
  '42501',
  null,
  'a member can''t manage putaway rules'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.bin_slots),
  0::bigint,
  'another organization sees no bin slots'
);

select * from finish();
rollback;
