-- onTaken: next_free (ADR 0430): an imported quote or invoice whose number is
-- already taken gets the next free number and a IMPORT_NUMBER_REASSIGNED
-- warning, and without it the item is still an error.
begin;
select plan(8);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select set_config('better_supabase.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'taken', '{}'::jsonb) ->> 'id'), true);
select better_supabase.mark_import_running(current_setting('better_supabase.run')::uuid);

create temporary table out (name text primary key, result jsonb) on commit drop;
grant all on out to service_role;

insert into out values ('first_quote', better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'quote',
  $json$[{"key":"q-a","data":{"number":"Q-2030-0001","currency":"EUR","lines":[{"description":"A","quantity":1,"unitAmount":100,"taxRateBps":0}]}}]$json$::jsonb));
select is((select (result ->> 'inserted')::int from out where name = 'first_quote'), 1, 'the first quote imports with its number');

insert into out values ('plain_clash', better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'quote',
  $json$[{"key":"q-b","data":{"number":"Q-2030-0001","currency":"EUR","lines":[{"description":"B","quantity":1,"unitAmount":100,"taxRateBps":0}]}}]$json$::jsonb));
select is((select jsonb_array_length(result -> 'errors') from out where name = 'plain_clash'), 1, 'without onTaken a taken number is an error');

insert into out values ('next_free', better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'quote',
  $json$[{"key":"q-c","data":{"number":"Q-2030-0001","onTaken":"next_free","currency":"EUR","lines":[{"description":"C","quantity":1,"unitAmount":100,"taxRateBps":0}]}}]$json$::jsonb));
select is((select (result ->> 'inserted')::int from out where name = 'next_free'), 1, 'next_free inserts the quote');
select is((select result -> 'warnings' -> 0 ->> 'code' from out where name = 'next_free'), 'IMPORT_NUMBER_REASSIGNED', 'and reports the new number');
select is((select count(*)::int from better_supabase.quotes where identifier = 'Q-2030-0001'), 1, 'the taken number stays on the first quote only');

insert into out values ('bad_mode', better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'quote',
  $json$[{"key":"q-d","data":{"number":"Q-2030-0002","onTaken":"overwrite","currency":"EUR","lines":[{"description":"D","quantity":1,"unitAmount":100,"taxRateBps":0}]}}]$json$::jsonb));
select is((select result -> 'errors' -> 0 ->> 'code' from out where name = 'bad_mode'), 'IMPORT_ITEM_INVALID', 'an unknown onTaken is refused');

insert into out values ('inv1', better_supabase.import_upsert_batch(
  current_setting('better_supabase.run')::uuid, 'invoice',
  $json$[{"key":"i-a","data":{"number":"INV-2030-0001","status":"issued","issuedOn":"2024-01-02","currency":"EUR","lines":[{"description":"A","quantity":1,"unitAmount":100,"taxRateBps":0}]}},
         {"key":"i-b","data":{"number":"INV-2030-0001","onTaken":"next_free","status":"issued","issuedOn":"2024-01-03","currency":"EUR","lines":[{"description":"B","quantity":1,"unitAmount":100,"taxRateBps":0}]}}]$json$::jsonb));
select is((select (result ->> 'inserted')::int from out where name = 'inv1'), 2, 'both invoices import');
select is((select count(*)::int from better_supabase.invoices where identifier = 'INV-2030-0001'), 1, 'the second invoice took another number');

select * from finish();
rollback;
