-- erase_data_subject across modules (ADR 0903): the consent signals of one
-- person are deleted, their consents and field changes are blanked and kept,
-- the data subject request is kept, a legal hold on a kind leaves its table
-- untouched and reports it, and nothing outside the request's tenant or person
-- changes. Acme is ...0001, Globex ...0002. Run with `supabase test db`.
begin;
select plan(22);

select ok(
  not has_function_privilege('anon', 'better_supabase.erase_data_subject(uuid)', 'execute'),
  'anon cannot execute erase_data_subject'
);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme: the person (customer a001) and another person (a002); Globex: a
-- person with the same record id as Acme's.
insert into better_supabase.consent_purposes (id, tenant_id, key, title)
values
  ('00000000-0000-4000-8000-0000000d0001', '00000000-0000-4000-8000-000000000001', 'marketing', 'Marketing'),
  ('00000000-0000-4000-8000-0000000d0002', '00000000-0000-4000-8000-000000000002', 'marketing', 'Marketing');

insert into better_supabase.consents (tenant_id, purpose_id, subject_type, subject_id, status, grantor_id, withdrawn_at, withdrawn_reason)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000d0001', 'customer', 'a001', 'withdrawn', '00000000-0000-4000-8000-0000000000a1', now(), 'moved'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000d0001', 'customer', 'a002', 'granted', '00000000-0000-4000-8000-0000000000a1', null, null),
  ('00000000-0000-4000-8000-000000000002', '00000000-0000-4000-8000-0000000d0002', 'customer', 'a001', 'granted', '00000000-0000-4000-8000-0000000000a3', null, null);

insert into better_supabase.consent_signals (tenant_id, subject_type, subject_id, kind, raw)
values
  ('00000000-0000-4000-8000-000000000001', 'customer', 'a001', 'gpc', '1'),
  ('00000000-0000-4000-8000-000000000001', 'customer', 'a001', 'tcf', 'CP...'),
  ('00000000-0000-4000-8000-000000000001', 'customer', 'a002', 'gpc', '1'),
  ('00000000-0000-4000-8000-000000000002', 'customer', 'a001', 'gpc', '1');

insert into better_supabase.field_changes (tenant_id, subject_type, subject_id, field, old_value, new_value, changed_by)
values
  ('00000000-0000-4000-8000-000000000001', 'customer', 'a001', 'name', '"Road"', '"Runner"', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000001', 'customer', 'a002', 'name', '"A"', '"B"', '00000000-0000-4000-8000-0000000000a1'),
  ('00000000-0000-4000-8000-000000000002', 'customer', 'a001', 'name', '"G"', '"H"', '00000000-0000-4000-8000-0000000000a3');

insert into better_supabase.data_subject_requests (id, tenant_id, kind, requester, subject_type, subject_id, due_at, verified_at)
values
  ('00000000-0000-4000-8000-0000000e0001', '00000000-0000-4000-8000-000000000001', 'erasure', 'road@example.com', 'customer', 'a001', now() + interval '30 days', now()),
  ('00000000-0000-4000-8000-0000000e0002', '00000000-0000-4000-8000-000000000001', 'erasure', 'road@example.com', 'customer', 'a001', now() + interval '30 days', null),
  ('00000000-0000-4000-8000-0000000e0003', '00000000-0000-4000-8000-000000000001', 'access', 'road@example.com', 'customer', 'a001', now() + interval '30 days', now()),
  ('00000000-0000-4000-8000-0000000e0004', '00000000-0000-4000-8000-000000000001', 'erasure', 'road@example.com', 'customer', 'a001', now() + interval '30 days', now());

-- Tenant isolation: Globex's owner cannot execute Acme's request.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e0001')$$,
  '42501',
  null,
  'another tenant cannot execute the erasure'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select throws_ok(
  $$select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e0002')$$,
  '55000',
  null,
  'an unverified request is refused'
);
select throws_ok(
  $$select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e0003')$$,
  '22023',
  null,
  'only an erasure request is executed'
);
select throws_ok(
  $$select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e00ff')$$,
  'P0002',
  null,
  'an unknown request is not found'
);

-- A legal hold on the audit kind holds the field changes and the request.
insert into ids select 'hold', (better_supabase.place_legal_hold('litigation', '00000000-0000-4000-8000-000000000001', 'audit') ->> 'id')::uuid;

create temporary table held_result (result jsonb) on commit drop;
grant all on held_result to service_role;

insert into held_result
select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e0001');

select is(
  (select result -> 'held' ->> 'better_supabase.field_changes' from held_result),
  '1',
  'a hold on the audit kind reports the field changes it protects'
);
select is(
  (select count(*)::integer from better_supabase.field_changes
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001' and old_value is not null),
  1,
  'held field changes keep their values'
);
select is(
  (select result -> 'held' ->> 'better_supabase.data_subject_requests' from held_result),
  '4',
  'the request table is held by the same kind'
);
select is(
  (select result -> 'removed' ->> 'better_supabase.consent_signals' from held_result),
  '2',
  'a table without a hold is still erased'
);

select better_supabase.release_legal_hold((select id from ids where name = 'hold'));

create temporary table done_result (result jsonb) on commit drop;
grant all on done_result to service_role;

insert into done_result
select better_supabase.erase_data_subject('00000000-0000-4000-8000-0000000e0001');

-- delete
select is(
  (select count(*)::integer from better_supabase.consent_signals
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001'),
  0,
  'the person''s consent signals are deleted'
);
select is(
  (select count(*)::integer from better_supabase.consent_signals
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a002'),
  1,
  'another person''s signals stay'
);

-- anonymize
select is(
  (select count(*)::integer from better_supabase.consents
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001'
     and grantor_id is null and withdrawn_reason is null),
  1,
  'the consent row stays with its personal columns blanked'
);
select is(
  (select status from better_supabase.consents
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001'),
  'withdrawn',
  'the consent keeps its status, so the evidence of the decision remains'
);
select is(
  (select count(*)::integer from better_supabase.field_changes
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001'
     and old_value is null and new_value is null and changed_by is null),
  1,
  'field changes stay as rows with the values blanked'
);

select is(
  (select result -> 'blanked' ->> 'better_supabase.field_changes' from done_result),
  '1',
  'the result lists the blanked field changes'
);
select is(
  (select result -> 'held' from done_result),
  '{}'::jsonb,
  'nothing is held once the hold is released'
);

-- keep
select is(
  (select count(*)::integer from better_supabase.data_subject_requests
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a001'),
  4,
  'the data subject requests are kept'
);
select is(
  (select result -> 'kept' ->> 'better_supabase.data_subject_requests' from done_result),
  '4',
  'the result lists the kept requests'
);

-- tenant and person isolation
select is(
  (select count(*)::integer from better_supabase.consents
   where tenant_id = '00000000-0000-4000-8000-000000000002' and grantor_id is not null),
  1,
  'another tenant''s consent is untouched'
);
select is(
  (select count(*)::integer from better_supabase.consent_signals
   where tenant_id = '00000000-0000-4000-8000-000000000002'),
  1,
  'another tenant''s signal is untouched'
);
select is(
  (select count(*)::integer from better_supabase.field_changes
   where tenant_id = '00000000-0000-4000-8000-000000000002' and old_value is not null),
  1,
  'another tenant''s field change is untouched'
);
select is(
  (select count(*)::integer from better_supabase.consents
   where tenant_id = '00000000-0000-4000-8000-000000000001' and subject_id = 'a002' and grantor_id is not null),
  1,
  'another person''s consent is untouched'
);

select * from finish();
rollback;
