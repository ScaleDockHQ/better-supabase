-- is_service_role() is true for the service role and a direct admin
-- connection, and false for every client role.
begin;
select plan(4);

select is(better_supabase.is_service_role(), true, 'a direct admin connection without a token is the service role');

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
select is(better_supabase.is_service_role(), true, 'a service role token is the service role');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select is(better_supabase.is_service_role(), false, 'an authenticated user is not the service role');

select set_config('request.jwt.claims', '{"role":"anon"}', true);
select is(better_supabase.is_service_role(), false, 'anon is not the service role');

select * from finish();
rollback;
