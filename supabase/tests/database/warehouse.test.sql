-- The warehouse module against the seed: the Acme admin (…a1) allocates stock
-- to a work order, picks it from a list and from a wave, and counts the stock
-- with a plan whose variance limit holds the posting. The Acme member (…a2)
-- can't manage waves or see lists assigned to nobody else's work, and the
-- Globex owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(16);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('pick_waves', 'pick_lists', 'pick_lines', 'count_plans')
     and rowsecurity),
  4::bigint,
  'the warehouse tables have RLS enabled'
);
select table_privs_are('better_supabase', 'pick_lists', 'anon', '{}'::text[],
  'anon has no privileges on pick lists');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.product', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Bolts', 'bolts', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.product')::uuid, null, 'BOLT', null, 'Bolts', null, null, true, false, null) ->> 'id', true);
select set_config('t.l', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH1', 'Warehouse', null, null) ->> 'id', true);
select better_supabase.adjust_stock(current_setting('t.v')::uuid, current_setting('t.l')::uuid, 8, 'receipt', null);
select better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 5, 'work_order', 'w1', 'l1', true);

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('list', (better_supabase.create_pick_list(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('locationId', current_setting('t.l'), 'documentType', 'work_order', 'documentId', 'w1')) ->> 'id')::uuid);
insert into ids
select 'line', (l ->> 'id')::uuid
from jsonb_array_elements(better_supabase.get_pick_list((select id from ids where name = 'list')) -> 'lines') l;

select is(
  (select jsonb_array_length(better_supabase.get_pick_list((select id from ids where name = 'list')) -> 'lines')),
  1,
  'the pick list has a line for the allocation'
);
select throws_ok(
  format($$select better_supabase.create_pick_list('00000000-0000-4000-8000-000000000001', jsonb_build_object('locationId', %L, 'documentType', 'work_order', 'documentId', 'w1'))$$, current_setting('t.l')),
  '55000',
  null,
  'an allocation on an open line is not picked twice'
);
select throws_ok(
  format($$select better_supabase.record_pick(%L, '{"quantity": 9}'::jsonb)$$, (select id from ids where name = 'line')),
  '22023',
  null,
  'a pick is at most what is left'
);
select is(
  (better_supabase.record_pick((select id from ids where name = 'line'), '{"quantity": 5}'::jsonb) -> 'lines' -> 0 ->> 'status'),
  'picked',
  'picking the whole quantity picks the line'
);
select is(
  better_supabase.complete_pick_list((select id from ids where name = 'list')) ->> 'status',
  'picked',
  'the pick list is completed'
);

select better_supabase.allocate_stock('00000000-0000-4000-8000-000000000001', current_setting('t.v')::uuid, current_setting('t.l')::uuid, 2, 'work_order', 'w2', 'l2', true);
insert into ids values ('wave', (better_supabase.create_pick_wave(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Morning', 'locationId', current_setting('t.l'))) ->> 'id')::uuid);
insert into ids values ('waveList', (better_supabase.create_pick_list(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('locationId', current_setting('t.l'), 'documentType', 'work_order', 'documentId', 'w2', 'waveId', (select id from ids where name = 'wave'))) ->> 'id')::uuid);
insert into ids
select 'waveLine', (l ->> 'id')::uuid
from jsonb_array_elements(better_supabase.get_pick_list((select id from ids where name = 'waveList')) -> 'lines') l;

select throws_ok(
  format($$select better_supabase.record_pick(%L, '{"quantity": 1}'::jsonb)$$, (select id from ids where name = 'waveLine')),
  '55000',
  null,
  'nothing is picked from a wave that is not released'
);
select is(
  better_supabase.release_pick_wave((select id from ids where name = 'wave')) ->> 'status',
  'released',
  'the wave is released'
);
select better_supabase.record_pick((select id from ids where name = 'waveLine'), '{"quantity": 1}'::jsonb);
select is(
  (better_supabase.complete_pick_list((select id from ids where name = 'waveList')) -> 'lines' -> 0 ->> 'status'),
  'short',
  'a line with less picked than asked for is short'
);
select is(
  (select w ->> 'status' from jsonb_array_elements(better_supabase.list_pick_waves('00000000-0000-4000-8000-000000000001')) w),
  'completed',
  'the wave completes with its last list'
);

insert into ids values ('plan', (better_supabase.create_count_plan(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('name', 'Weekly', 'locationId', current_setting('t.l'), 'everyDays', 7)) ->> 'id')::uuid);
insert into ids values ('count', (better_supabase.run_count_plan((select id from ids where name = 'plan')) ->> 'countId')::uuid);
select better_supabase.record_count_line((select id from ids where name = 'count'),
  jsonb_build_object('variantId', current_setting('t.v'), 'counted', 6));
select is(
  (better_supabase.get_cycle_count_variance((select id from ids where name = 'count')) ->> 'overLimit')::boolean,
  true,
  'a count 25 percent under the books is over the 5 percent limit'
);
select throws_ok(
  format($$select better_supabase.post_cycle_count(%L)$$, (select id from ids where name = 'count')),
  '55000',
  null,
  'a count over the limit waits for an approval'
);
select is(
  (better_supabase.post_cycle_count((select id from ids where name = 'count'), true) ->> 'approved')::boolean,
  true,
  'with approval the count posts'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.create_pick_wave('00000000-0000-4000-8000-000000000001', jsonb_build_object('name', 'Nope', 'locationId', %L))$$, current_setting('t.l')),
  '42501',
  null,
  'a member can''t manage waves'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.pick_lists),
  0::bigint,
  'another organization sees no pick lists'
);

select * from finish();
rollback;
