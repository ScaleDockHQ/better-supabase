-- Archive, restore and purge for funding claims (ADR 1044). Only a claim the
-- funder answered is archived; an archived claim leaves the list and is not
-- invoiced; a draft is removed with `purge_funding_claim`. Run with
-- `supabase test db`.
begin;
select plan(10);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config('request.jwt.claims', '{"role":"service_role"}', true);

set local session_replication_role = replica;
insert into better_supabase.funding_claims (id, tenant_id, funder_id, number, period_start, period_end, format, status, currency)
values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f0a1', 'Y2-A', '2027-01-01', '2027-01-31', 'x', 'accepted', 'EUR'),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f0a1', 'Y2-D', '2027-02-01', '2027-02-28', 'x', 'draft', 'EUR');
set local session_replication_role = origin;

select throws_ok(
  $$select better_supabase.archive_funding_claim('00000000-0000-4000-8000-00000000f002')$$,
  '22023', null, 'a draft claim is not archived'
);

select isnt(
  better_supabase.archive_funding_claim('00000000-0000-4000-8000-00000000f001') ->> 'archivedAt',
  null, 'archive sets archivedAt'
);
select is(pg_temp.n('funding_claim.archived'), 1, 'archive records funding_claim.archived once');
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_funding_claims('00000000-0000-4000-8000-000000000001'))
    where value ->> 'id' = '00000000-0000-4000-8000-00000000f001'),
  0, 'the list hides an archived claim'
);
select is(
  (select count(*)::integer from jsonb_array_elements(better_supabase.list_funding_claims('00000000-0000-4000-8000-000000000001', null, null, true))
    where value ->> 'id' = '00000000-0000-4000-8000-00000000f001'),
  1, 'include_archived lists it'
);
select better_supabase.archive_funding_claim('00000000-0000-4000-8000-00000000f001');
select is(pg_temp.n('funding_claim.archived'), 1, 'archiving twice records nothing more');

select throws_ok(
  $$select better_supabase.invoice_funding_claim('00000000-0000-4000-8000-00000000f001', null)$$,
  '22023', null, 'an archived claim is not invoiced'
);

select is(
  better_supabase.restore_funding_claim('00000000-0000-4000-8000-00000000f001') ->> 'archivedAt',
  null, 'restore clears archivedAt'
);
select is(pg_temp.n('funding_claim.restored'), 1, 'restore records funding_claim.restored once');

select is(
  better_supabase.purge_funding_claim('00000000-0000-4000-8000-00000000f002'),
  true, 'purge removes a draft claim'
);

select * from finish();
rollback;
