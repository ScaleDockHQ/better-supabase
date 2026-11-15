-- Archiving an agent (ADR 1080): an archived agent leaves list_agents and
-- refuses save, publish, install and rate, restore brings it back, and purge is
-- the hard delete behind the purge key, which a plain member lacks even for
-- their own agent. Run with `supabase test db`.
begin;
select plan(14);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.base',
  jsonb_array_length(better_supabase.list_agents('00000000-0000-4000-8000-000000000001', 'mine'))::text, true);
select set_config('test.agent', better_supabase.save_agent(
  '00000000-0000-4000-8000-000000000001', null,
  '{"slug": "archive-me", "name": "Archive me"}') ->> 'id', true);

select isnt(
  better_supabase.archive_agent(current_setting('test.agent')::uuid) ->> 'archived_at', null,
  'the owner archives their agent'
);
select is(pg_temp.n('agent.archived'), 1, 'archiving records agent.archived');
select is(
  jsonb_array_length(better_supabase.list_agents('00000000-0000-4000-8000-000000000001', 'mine')), current_setting('test.base')::integer,
  'the archived agent leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_agents('00000000-0000-4000-8000-000000000001', 'mine', null, 50, true)), current_setting('test.base')::integer + 1,
  'include_archived lists it again'
);
select isnt(
  better_supabase.get_agent(current_setting('test.agent')::uuid), null,
  'get_agent still reads it by id'
);
select throws_ok(
  format('select better_supabase.save_agent(%L, %L, %L)', '00000000-0000-4000-8000-000000000001',
    current_setting('test.agent'), '{"name": "Renamed"}'),
  '55000', null, 'save_agent refuses an archived agent'
);
select throws_ok(
  format('select better_supabase.rate_agent(%L, 4)', current_setting('test.agent')),
  '55000', null, 'rate_agent refuses an archived agent'
);
select throws_ok(
  format('select better_supabase.install_agent(%L, %L)', '00000000-0000-4000-8000-000000000001', current_setting('test.agent')),
  '55000', null, 'install_agent refuses an archived agent'
);

select better_supabase.archive_agent(current_setting('test.agent')::uuid);
select is(pg_temp.n('agent.archived'), 1, 'archiving twice records one event');

select isnt(
  better_supabase.restore_agent(current_setting('test.agent')::uuid) ->> 'id', null,
  'restoring returns the agent'
);
select is(pg_temp.n('agent.restored'), 1, 'restoring records agent.restored');

select throws_ok(
  format('select better_supabase.purge_agent(%L)', current_setting('test.agent')),
  '42501', null, 'a member can''t purge even their own agent'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.purge_agent(current_setting('test.agent')::uuid), true,
  'a moderator purges the agent'
);
select is(pg_temp.n('agent.purged'), 1, 'purge records agent.purged');

select * from finish();
rollback;
