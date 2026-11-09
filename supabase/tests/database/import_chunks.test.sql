-- Stored import chunks (ADR 0437): store, claim, complete and process give a
-- worker batches that survive a retry. Processing a done chunk answers what it
-- answered, a claimed chunk is not taken twice, a stale claim is taken over, a
-- failure leaves the chunk pending, and no API role can touch the table.
begin;
select plan(13);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('bsb.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'chunks', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select is(
  better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0,
    (select jsonb_agg(jsonb_build_object('key', 'c0-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Chunk ' || g, 'kvk', 'c0' || g), 'refs', '{}'::jsonb)) from generate_series(1, 10) g)),
  true, 'a chunk is stored');
select better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1,
  (select jsonb_agg(jsonb_build_object('key', 'c1-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Chunk b' || g, 'kvk', 'c1' || g), 'refs', '{}'::jsonb)) from generate_series(1, 10) g));
select is(better_supabase.import_chunk_progress(current_setting('bsb.run')::uuid), '{"pending": 2, "claimed": 0, "done": 0}'::jsonb, 'two chunks wait');

select is(better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1, '[]'::jsonb), true, 'a pending chunk is replaced');
select is((select jsonb_array_length(items) from better_supabase.import_chunks where chunk = 1 and run_id = current_setting('bsb.run')::uuid), 0, 'with the new items');
select better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1,
  (select jsonb_agg(jsonb_build_object('key', 'c1-' || g, 'scope', '', 'data', jsonb_build_object('name', 'Chunk b' || g, 'kvk', 'c1' || g), 'refs', '{}'::jsonb)) from generate_series(1, 10) g));

-- Claiming: once, then not again while it is held.
select isnt(better_supabase.claim_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0), null, 'a pending chunk is claimed');
select is(better_supabase.claim_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0), null, 'a claimed chunk is not claimed again');
update better_supabase.import_chunks set claimed_at = now() - interval '1 hour' where run_id = current_setting('bsb.run')::uuid and chunk = 0;
select isnt(better_supabase.claim_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0), null, 'a stale claim is taken over');

-- Processing writes the chunk and marks it done; again it answers the same.
select is((better_supabase.process_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1) ->> 'inserted')::int, 10, 'processing writes the chunk');
select is(
  (select jsonb_build_array(count(*), min(status)) from better_supabase.import_chunks where run_id = current_setting('bsb.run')::uuid and chunk = 1),
  '[1, "done"]'::jsonb, 'and marks it done');
select is((better_supabase.process_import_chunk(current_setting('bsb.run')::uuid, 'customer', 1) ->> 'done')::boolean, true, 'processing a done chunk is a no-op');

-- A failure leaves the chunk pending: the run is finished, so the batch refuses.
select better_supabase.complete_import_chunk(current_setting('bsb.run')::uuid, 'customer', 0, '{}'::jsonb);
select better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', 2, '[]'::jsonb);
select better_supabase.finish_import_run(current_setting('bsb.run')::uuid);
select throws_ok(
  format($$select better_supabase.process_import_chunk(%L::uuid, 'customer', 2)$$, current_setting('bsb.run')),
  '55000', null, 'a finished run refuses the chunk');
select is((select status from better_supabase.import_chunks where run_id = current_setting('bsb.run')::uuid and chunk = 2), 'pending', 'the failed chunk stays pending');

reset role;
set local role authenticated;
select throws_ok($$select count(*) from better_supabase.import_chunks$$, '42501', null, 'an API role cannot read the chunks');

select * from finish();
rollback;
