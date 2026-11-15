-- Archiving a care rule (ADR 1054): an archived rule leaves list_care_rules,
-- save_care_rule refuses it, restore brings it back, and purge is the hard
-- delete behind manage. Run with `supabase test db`.
begin;
select plan(13);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- The local stack may hold seeded rules, so the lists are compared to this count.
select set_config('test.base',
  jsonb_array_length(better_supabase.list_care_rules('00000000-0000-4000-8000-000000000001'))::text, true);

select set_config('test.med', better_supabase.save_medication(
  '00000000-0000-4000-8000-000000000001', 'Archive paracetamol', 'mg') ->> 'id', true);
select set_config('test.rule', better_supabase.save_care_rule(
  '00000000-0000-4000-8000-000000000001',
  jsonb_build_object('kind', 'dose_range', 'medicationIds', jsonb_build_array(current_setting('test.med')), 'maxDose', 1000)
) ->> 'id', true);

select isnt(
  better_supabase.archive_care_rule(current_setting('test.rule')::uuid) ->> 'archivedAt', null,
  'archiving sets archivedAt'
);
select is(pg_temp.n('care_rule.archived'), 1, 'archiving records care_rule.archived');
select is(
  jsonb_array_length(better_supabase.list_care_rules('00000000-0000-4000-8000-000000000001')), current_setting('test.base')::integer,
  'the archived rule leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_care_rules('00000000-0000-4000-8000-000000000001', true)), current_setting('test.base')::integer + 1,
  'include_archived lists it again'
);
select throws_ok(
  format($$select better_supabase.save_care_rule('00000000-0000-4000-8000-000000000001',
    jsonb_build_object('id', %L, 'kind', 'dose_range', 'medicationIds', jsonb_build_array(%L), 'maxDose', 500))$$,
    current_setting('test.rule'), current_setting('test.med')),
  '55000', null, 'save_care_rule refuses an archived rule'
);

select better_supabase.archive_care_rule(current_setting('test.rule')::uuid);
select is(pg_temp.n('care_rule.archived'), 1, 'archiving twice records one event');

select isnt(
  better_supabase.restore_care_rule(current_setting('test.rule')::uuid) ->> 'id', null,
  'restoring returns the rule'
);
select is(pg_temp.n('care_rule.restored'), 1, 'restoring records care_rule.restored');
select is(
  jsonb_array_length(better_supabase.list_care_rules('00000000-0000-4000-8000-000000000001')), current_setting('test.base')::integer + 1,
  'the restored rule is listed again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format('select better_supabase.archive_care_rule(%L)', current_setting('test.rule')),
  'P0002', null, 'a member without the read key can''t see the rule to archive it'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  format('select better_supabase.restore_care_rule(%L)', current_setting('test.rule')),
  'P0002', null, 'another organization can''t see the rule'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select isnt(
  better_supabase.purge_care_rule(current_setting('test.rule')::uuid) ->> 'id', null,
  'purge removes the rule'
);
select is(pg_temp.n('care_rule.purged'), 1, 'purge records care_rule.purged');

select * from finish();
rollback;
