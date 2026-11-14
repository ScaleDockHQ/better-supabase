-- The teams module: the owner (…00a1) of Acme (…0001) archives a team, which
-- keeps the row, and purges it, which removes it; the member (…00a2) can do
-- neither. `delete_team` is gone (ADR 0851).
begin;
select plan(5);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.team', better_supabase.create_team(
  '00000000-0000-4000-8000-000000000001', 'Platform', null, 'platform'
) ->> 'id', true);

select is(
  better_supabase.archive_team(current_setting('test.team')::uuid),
  true,
  'the owner archives a team'
);
select is(
  (select count(*)::integer from better_supabase.teams where id = current_setting('test.team')::uuid),
  1,
  'an archived team keeps its row'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.purge_team(%L)$$, current_setting('test.team')),
  '42501',
  'not allowed to manage teams',
  'the member cannot purge a team'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.purge_team(current_setting('test.team')::uuid),
  true,
  'the owner purges a team'
);
select hasnt_function(
  'better_supabase',
  'delete_team',
  array['uuid'],
  'delete_team is gone'
);

select * from finish();
rollback;
