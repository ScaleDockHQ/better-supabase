-- Two edges of an import run: a dry run that is cancelled leaves no rows and no
-- record map entries, and two runs of one source started in the same second
-- keep their own ids and counts (briefs 1.3 and 7.4).
begin;
select plan(6);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('bsb.dry', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'edges', '{"dryRun":true}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.dry')::uuid);
select better_supabase.import_upsert_batch(current_setting('bsb.dry')::uuid, 'customer',
  '[{"key":"e1","data":{"name":"Edge dry one","kvk":"e1"}},{"key":"e2","data":{"name":"Edge dry two","kvk":"e2"}}]'::jsonb);
select is((select count(*)::int from public.customers where name like 'Edge dry%'), 0, 'a dry run writes no customer');
select is((select count(*)::int from better_supabase.import_records where source = 'edges'), 0, 'a dry run leaves no record map entry');

select better_supabase.cancel_import_run(current_setting('bsb.dry')::uuid);
select is((select status::text from better_supabase.import_runs where id = current_setting('bsb.dry')::uuid), 'canceled', 'the dry run cancels');
select is((select count(*)::int from public.customers where name like 'Edge dry%') + (select count(*)::int from better_supabase.import_records where source = 'edges'), 0, 'cancelling leaves nothing behind');

select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'edges-same', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer', '[{"key":"s1","data":{"name":"Edge same one","kvk":"s1"}}]'::jsonb);
select better_supabase.finish_import_run(current_setting('bsb.a')::uuid);

-- The second run of the source starts in the same second as the first ended.
select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'edges-same', '{}'::jsonb) ->> 'id'), true);
select isnt(current_setting('bsb.a'), current_setting('bsb.b'), 'a run started right after another gets its own id');
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
select better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer', '[{"key":"s1","data":{"name":"Edge same one","kvk":"s1"}},{"key":"s2","data":{"name":"Edge same two","kvk":"s2"}}]'::jsonb);
select is(
  (select jsonb_build_array(
    (select (counts -> 'customer' ->> 'inserted')::int from better_supabase.import_runs where id = current_setting('bsb.a')::uuid),
    (select (counts -> 'customer' ->> 'inserted')::int from better_supabase.import_runs where id = current_setting('bsb.b')::uuid),
    (select (counts -> 'customer' ->> 'unchanged')::int from better_supabase.import_runs where id = current_setting('bsb.b')::uuid))),
  '[1, 1, 1]'::jsonb,
  'each run keeps its own counts; the repeated key is unchanged in the second'
);

select * from finish();
rollback;
