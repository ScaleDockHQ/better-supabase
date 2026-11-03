-- Leases on any (scope, key): claimed, busy, completed, takeover after expiry,
-- and a service-only grant. Needs the queue module at version 10 or later, so
-- run it after the fixture is regenerated.
begin;
select plan(13);

create temporary table held (token uuid) on commit drop;
grant all on held to service_role;

set local role anon;
select throws_ok(
  $$select * from better_supabase.claim_lease('drain', 't1')$$,
  '42501',
  null,
  'anon-facing roles cannot claim a lease'
);

reset role;
set local role service_role;

insert into held select lease_holder from better_supabase.claim_lease('drain', 't1', 60);
select isnt((select token from held), null, 'the first claim returns a holder token');
select is(
  (select lease_state from better_supabase.claim_lease('drain', 't1', 60)),
  'busy',
  'a second claim on a held lease answers busy'
);
select cmp_ok(
  (select retry_after_ms from better_supabase.claim_lease('drain', 't1', 60)),
  '>',
  0,
  'busy says when the lease ends'
);
select is(
  (select lease_state from better_supabase.claim_lease('drain', 't2', 60)),
  'claimed',
  'another key is independent'
);
select ok(
  better_supabase.extend_lease_claim('drain', 't1', (select token from held), 120),
  'the holder extends its lease'
);
select ok(
  not better_supabase.extend_lease_claim('drain', 't1', gen_random_uuid(), 120),
  'another token cannot extend it'
);

-- A transaction keeps now() fixed, so age the lease by hand.
update better_supabase.job_leases set expires_at = now() - interval '1 second' where key = 't1';
select is(
  (select lease_state from better_supabase.claim_lease('drain', 't1', 60)),
  'claimed',
  'an expired lease is taken over'
);
select ok(
  not better_supabase.complete_lease('drain', 't1', (select token from held), 60),
  'the former holder can no longer complete it'
);

select ok(
  better_supabase.complete_lease('drain', 't1', (select holder from better_supabase.job_leases where key = 't1'), 60),
  'the new holder completes it'
);
select is(
  (select lease_state from better_supabase.claim_lease('drain', 't1', 60)),
  'completed',
  'a completed lease stays completed for its keep time'
);
select ok(
  better_supabase.release_lease_claim('drain', 't2', (select holder from better_supabase.job_leases where key = 't2')),
  'the holder releases a lease'
);
select is(
  (select lease_state from better_supabase.claim_lease('drain', 't2', 60)),
  'claimed',
  'a released key can be claimed at once'
);

select * from finish();
rollback;
