-- A 50,000-item import in 50 chunks of 1,000 (ADR 1213). While the chunks
-- wait they hold their items; once each is done it keeps only its result, so
-- the run's chunks shrink to a few bytes. The stored and the kept sizes go to
-- SCALE_BYTES diag lines, the time to complete the chunks to SCALE_MS.
begin;
select plan(2);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('bsb.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'scale-chunks', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

select count(better_supabase.store_import_chunk(current_setting('bsb.run')::uuid, 'customer', c,
  (select jsonb_agg(jsonb_build_object('key', 'scale-' || c || '-' || g, 'scope', '',
    'data', jsonb_build_object('name', 'Scale customer ' || c || '-' || g, 'kvk', 'sc' || c || g, 'email', 'scale' || c || '-' || g || '@example.com'),
    'refs', '{}'::jsonb)) from generate_series(1, 1000) g)))
from generate_series(0, 49) c;

create temp table marks (name text, t timestamptz, bytes bigint);
insert into marks values ('stored', clock_timestamp(),
  (better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'chunks' ->> 'bytes')::bigint);

select count(better_supabase.claim_import_chunk(current_setting('bsb.run')::uuid, 'customer', c))
from generate_series(0, 49) c;
select count(better_supabase.complete_import_chunk(current_setting('bsb.run')::uuid, 'customer', c, '{"inserted": 1000}'::jsonb))
from generate_series(0, 49) c;
insert into marks values ('done', clock_timestamp(),
  (better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'chunks' ->> 'bytes')::bigint);

select ok((select bytes from marks where name = 'stored') > 500000, 'the waiting chunks hold their 50,000 items');
select is((select bytes from marks where name = 'done'), 0::bigint, 'the done chunks hold no items');

select diag('SCALE_BYTES import_chunks_stored_50000=' || (select bytes from marks where name = 'stored'));
select diag('SCALE_BYTES import_chunks_done_50000=' || (select bytes from marks where name = 'done'));
select diag('SCALE_MS import_chunks_complete_50=' || round(extract(epoch from (select t from marks where name = 'done') - (select t from marks where name = 'stored')) * 1000));

select * from finish();
rollback;
