-- actor_may_write() decides by act.kind first: support writes only with
-- read_only false, an agent unless read_only is true, and impersonation or
-- an unknown kind never. read_only is compared as JSON, so a string fails closed.
begin;
select plan(15);

select is(better_supabase.actor_may_write(), true, 'no token may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}', true);
select is(better_supabase.actor_may_write(), true, 'no actor may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","client_id":"client-1"}', true);
select is(better_supabase.actor_may_write(), true, 'an OAuth client may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"support","sub":"admin-1","session_id":"s1"}}', true);
select is(better_supabase.actor_may_write(), false, 'support without read_only may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"support","sub":"admin-1","session_id":"s1","read_only":true}}', true);
select is(better_supabase.actor_may_write(), false, 'support with read_only true may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"support","sub":"admin-1","session_id":"s1","read_only":false}}', true);
select is(better_supabase.actor_may_write(), true, 'support with read_only false may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"support","sub":"admin-1","session_id":"s1","read_only":"false"}}', true);
select is(better_supabase.actor_may_write(), false, 'support with read_only as a string may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"impersonation","sub":"admin-1"}}', true);
select is(better_supabase.actor_may_write(), false, 'impersonation may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"impersonation","sub":"admin-1","read_only":false}}', true);
select is(better_supabase.actor_may_write(), false, 'impersonation with read_only false may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"agent","sub":"agent-7"}}', true);
select is(better_supabase.actor_may_write(), true, 'an agent without read_only may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"agent","sub":"agent-7","read_only":false}}', true);
select is(better_supabase.actor_may_write(), true, 'an agent with read_only false may write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"agent","sub":"agent-7","read_only":true}}', true);
select is(better_supabase.actor_may_write(), false, 'an agent with read_only true may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"agent","sub":"agent-7","read_only":"true"}}', true);
select is(better_supabase.actor_may_write(), false, 'an agent with read_only as a string may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"sub":"admin-1","session_id":"s1"}}', true);
select is(better_supabase.actor_may_write(), false, 'a session_id without kind may not write');

select set_config('request.jwt.claims', '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","act":{"kind":"robot","sub":"robot-1","read_only":false}}', true);
select is(better_supabase.actor_may_write(), false, 'an unknown kind may not write');

select * from finish();
rollback;
