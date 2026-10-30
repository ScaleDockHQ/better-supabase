-- The contracts module against the seed: an Acme member (…a2) drafts and
-- submits, the Acme owner (…a1) activates and terminates, and the Globex
-- owner (…a3) sees none of it. Run with `supabase test db`.
begin;
select plan(18);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename in ('contracts', 'contract_obligations') and rowsecurity),
  2::bigint,
  'the contracts tables have RLS enabled'
);
select table_privs_are('better_supabase', 'contracts', 'anon', '{}'::text[],
  'anon has no privileges on contracts');
select table_privs_are('better_supabase', 'contract_obligations', 'anon', '{}'::text[],
  'anon has no privileges on obligations');
select function_privs_are('better_supabase', 'run_contract_renewals', array['date'], 'authenticated', '{}'::text[],
  'only the service role runs renewals');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('msa', (better_supabase.create_contract('00000000-0000-4000-8000-000000000001', jsonb_build_object(
  'title', 'Master services agreement',
  'counterpartyType', 'customer', 'counterpartyId', '00000000-0000-4000-8000-00000000a001',
  'value', '1200000', 'currency', 'eur',
  'startsOn', current_date - 366, 'endsOn', current_date - 1, 'autoRenew', true, 'renewalMonths', 12, 'noticeDays', 30
)) ->> 'id')::uuid);

select is(
  (select currency || ':' || value::text || ':' || status from better_supabase.contracts where id = (select id from ids)),
  'EUR:1200000:draft',
  'a member drafts a contract with its value in minor units'
);
select throws_ok(
  $$select better_supabase.create_contract('00000000-0000-4000-8000-000000000001',
    '{"title":"Poached","counterpartyType":"customer","counterpartyId":"00000000-0000-4000-8000-00000000a003"}'::jsonb)$$,
  '22023',
  null,
  'a counterparty from another organization is refused'
);
select is(
  (better_supabase.transition_contract((select id from ids), 'submit') ->> 'status'),
  'in_review',
  'a member submits the draft for review'
);
select throws_ok(
  $$select better_supabase.transition_contract((select id from ids), 'activate')$$,
  '42501',
  null,
  'a member cannot activate a contract'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.transition_contract((select id from ids), 'activate') ->> 'status'),
  'active',
  'the owner activates a contract signed elsewhere'
);
select is(
  (better_supabase.save_contract_obligation((select id from ids), 'Quarterly report', current_date - 1,
    '00000000-0000-4000-8000-0000000000a2') ->> 'status'),
  'open',
  'the owner adds an obligation for a member'
);
select is(
  (select better_supabase.list_contract_obligations('00000000-0000-4000-8000-000000000001', open_only => true) -> 0 ->> 'overdue'),
  'true',
  'an open obligation past its due date is overdue'
);
grant select on ids to authenticated;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.contracts),
  0::bigint,
  'the Globex owner reads no Acme contracts'
);
select throws_ok(
  $$select better_supabase.update_contract((select id from ids), '{"title":"Mine now"}'::jsonb)$$,
  '42501',
  null,
  'the Globex owner cannot change an Acme contract'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  (select count(*) from better_supabase.reminders where subject_type = 'contract' and subject_id = (select id from ids)::text
     and user_id = '00000000-0000-4000-8000-0000000000a2' and offset_minutes = 20160),
  1::bigint,
  'an active contract with an end date reminds its owner two weeks before the notice deadline'
);
select is(
  better_supabase.run_contract_renewals(),
  '{"expired": 0, "renewed": 1}'::jsonb,
  'the renewal run renews an auto-renewing contract past its end date'
);
select is(
  (select (ends_on = (current_date - 1 + interval '12 months')::date) and renewed_count = 1
   from better_supabase.contracts where id = (select id from ids)),
  true,
  'the renewal moves the end date by the renewal period'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (better_supabase.transition_contract((select id from ids), 'terminate', 'Replaced') ->> 'terminationReason'),
  'Replaced',
  'the owner terminates the contract with a reason'
);
select throws_ok(
  $$select better_supabase.transition_contract((select id from ids), 'terminate')$$,
  '55000',
  null,
  'a terminated contract takes no further step'
);

select * from finish();
rollback;
