-- The import follow-ups of ADR 1213: list_import_conflicts pages a run's
-- conflicts by keyset, and a stock count without a location goes to the
-- organization's only active location. The admin (…00a1) of Acme (…0001)
-- reads the conflicts; the service role runs the import.
begin;
select plan(8);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('t.p', better_supabase.save_product('00000000-0000-4000-8000-000000000001', null, 'Valve', 'valve-1209', null, 'physical', null) ->> 'id', true);
select set_config('t.v', better_supabase.save_variant(current_setting('t.p')::uuid, null, 'VALVE-1209', null, 'Valve', null, 500, true, false, null) ->> 'id', true);
select set_config('t.loc', better_supabase.save_location('00000000-0000-4000-8000-000000000001', null, 'WH1209', 'Warehouse', null, null) ->> 'id', true);
select set_config('t.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'conflicts-1209', '{}'::jsonb) ->> 'id'), true);

reset role;
insert into better_supabase.import_run_issues (run_id, tenant_id, source, entity, key, kind, code, message, created_at)
select current_setting('t.run')::uuid, '00000000-0000-4000-8000-000000000001', 'conflicts-1209',
  case when g % 2 = 0 then 'customer' else 'invoice' end, 'k-' || g, 'conflict', 'IMPORT_CONFLICT', 'changed since the last import',
  now() - make_interval(secs => 100 - g)
from generate_series(1, 5) g;
insert into better_supabase.import_run_issues (run_id, tenant_id, source, entity, key, kind, code, message)
values (current_setting('t.run')::uuid, '00000000-0000-4000-8000-000000000001', 'conflicts-1209', 'customer', 'w-1', 'warning', 'IMPORT_WARNING', 'a warning');
update better_supabase.inventory_locations set active = false
where tenant_id = '00000000-0000-4000-8000-000000000001' and id <> current_setting('t.loc')::uuid;

set local role authenticated;
select set_config('t.page', better_supabase.list_import_conflicts(current_setting('t.run')::uuid, null, null, 2)::text, true);
select is(
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(current_setting('t.page')::jsonb -> 'rows') r),
  '["k-1", "k-2"]'::jsonb, 'the first page holds the oldest conflicts');
select isnt(current_setting('t.page')::jsonb ->> 'next_cursor', null, 'and a cursor to the next page');
select is(
  (select jsonb_agg(r ->> 'key') from jsonb_array_elements(
    better_supabase.list_import_conflicts(current_setting('t.run')::uuid, null, current_setting('t.page')::jsonb ->> 'next_cursor', 10) -> 'rows') r),
  '["k-3", "k-4", "k-5"]'::jsonb, 'the next page continues after the cursor, without the warning');
select is(
  better_supabase.list_import_conflicts(current_setting('t.run')::uuid, null, current_setting('t.page')::jsonb ->> 'next_cursor', 10) -> 'next_cursor',
  'null'::jsonb, 'the last page has no cursor');
select is(
  jsonb_array_length(better_supabase.list_import_conflicts(current_setting('t.run')::uuid, 'customer', null, 10) -> 'rows'),
  2, 'an entity narrows the conflicts');

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('t.run')::uuid);
select is(
  (better_supabase.import_upsert_batch(current_setting('t.run')::uuid, 'stock_count',
    '[{"key":"count-1209","data":{"note":"No location","lines":[{"sku":"VALVE-1209","counted":4}]}}]'::jsonb) ->> 'inserted')::int,
  1, 'a count without a location imports');
select is(
  (select location_id from better_supabase.stock_counts where tenant_id = '00000000-0000-4000-8000-000000000001' and note = 'No location'),
  current_setting('t.loc')::uuid, 'into the only active location');

reset role;
update better_supabase.inventory_locations set active = true
where tenant_id = '00000000-0000-4000-8000-000000000001';
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(
  (better_supabase.import_upsert_batch(current_setting('t.run')::uuid, 'stock_count',
    '[{"key":"count-1209b","data":{"lines":[{"sku":"VALVE-1209","counted":4}]}}]'::jsonb) -> 'errors' -> 0 ->> 'code'),
  'IMPORT_ITEM_INVALID', 'with two active locations a count needs one');

select * from finish();
rollback;
