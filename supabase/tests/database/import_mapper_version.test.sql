-- A run records its mapper version, reapply_import_records clears the hashes of
-- records an older version wrote so the next run rewrites them, and
-- export_import_hashes lists the record map (ADR 0439).
begin;
select plan(9);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('bsb.a', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'mapper', '{"mapperVersion":"v1"}'::jsonb) ->> 'id'), true);
select is((better_supabase.get_import_run(current_setting('bsb.a')::uuid) ->> 'mapperVersion'), 'v1', 'the run keeps its mapper version');
select better_supabase.mark_import_running(current_setting('bsb.a')::uuid);
select better_supabase.import_upsert_batch(current_setting('bsb.a')::uuid, 'customer',
  '[{"key":"m1","data":{"name":"Mapper one","kvk":"m1"}},{"key":"m2","data":{"name":"Mapper two","kvk":"m2"}}]'::jsonb);
select better_supabase.finish_import_run(current_setting('bsb.a')::uuid);

select is((select count(*)::int from better_supabase.export_import_hashes('00000000-0000-4000-8000-000000000001', 'mapper')), 2, 'the hashes are listed');
select is((select count(*)::int from better_supabase.export_import_hashes('00000000-0000-4000-8000-000000000001', 'mapper', 'nothing')), 0, 'an entity filter narrows them');
select is((select (h ->> 'hash') ~ '^[0-9a-f]{64}$' from better_supabase.export_import_hashes('00000000-0000-4000-8000-000000000001', 'mapper') h limit 1), true, 'each carries its hash');

-- The same mapper version: nothing to reapply.
select is(better_supabase.reapply_import_records('00000000-0000-4000-8000-000000000001', 'mapper', 'v1'), 0, 'records of the current version stay');

-- A new version: the next run counts every record as changed and rewrites it.
select is(better_supabase.reapply_import_records('00000000-0000-4000-8000-000000000001', 'mapper', 'v2'), 2, 'records of an older version are cleared');

select set_config('bsb.b', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'mapper', '{"mapperVersion":"v2"}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.b')::uuid);
select set_config('bsb.counts', (better_supabase.import_upsert_batch(current_setting('bsb.b')::uuid, 'customer',
  '[{"key":"m1","data":{"name":"Mapper one fixed","kvk":"m1"}},{"key":"m2","data":{"name":"Mapper two","kvk":"m2"}}]'::jsonb))::text, true);
select is((current_setting('bsb.counts')::jsonb ->> 'updated')::int, 2, 'both records are rewritten by the new version');
select is((select name from public.customers where kvk = 'm1'), 'Mapper one fixed', 'with the fixed value');
select is(better_supabase.reapply_import_records('00000000-0000-4000-8000-000000000001', 'mapper', 'v2'), 0, 'after the rewrite the version is current');

select * from finish();
rollback;
