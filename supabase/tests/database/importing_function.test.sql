-- better_supabase.importing() is true only inside a service-role import
-- session; a user who sets the setting is never importing (ADR 0428).
begin;
select plan(4);

select is(better_supabase.importing(), false, 'false outside a session');

select set_config('better_supabase.import_run', '00000000-0000-4000-8000-00000000e001', true);
select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
set local role authenticated;
select is(better_supabase.importing(), false, 'a user who sets the setting is not importing');

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select is(better_supabase.importing(), true, 'the service role with a session is importing');

select set_config('better_supabase.import_run', '', true);
select is(better_supabase.importing(), false, 'false again once the session ends');

select * from finish();
rollback;
