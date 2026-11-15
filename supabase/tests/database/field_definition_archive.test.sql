-- Archiving a field definition (ADR 1083): an archived field leaves
-- list_field_definitions, save_field_definition and set_field_value refuse it,
-- its values stay readable, restore brings it back and purge is the hard
-- delete that takes the values with it. Run with `supabase test db`.
begin;
select plan(14);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.base',
  jsonb_array_length(better_supabase.list_field_definitions('00000000-0000-4000-8000-000000000001', 'person'))::text, true);
select set_config('test.def', better_supabase.save_field_definition(
  '00000000-0000-4000-8000-000000000001', 'person', 'archive_plan', 'Plan', 'text', false) ->> 'id', true);
select better_supabase.set_field_value(
  '00000000-0000-4000-8000-000000000001', 'contact', 'c-archive', current_setting('test.def')::uuid, 'basic');

select isnt(
  better_supabase.archive_field_definition(current_setting('test.def')::uuid) ->> 'archivedAt', null,
  'archiving sets archivedAt'
);
select is(pg_temp.n('field_definition.archived'), 1, 'archiving records field_definition.archived');
select is(
  jsonb_array_length(better_supabase.list_field_definitions('00000000-0000-4000-8000-000000000001', 'person')),
  current_setting('test.base')::integer,
  'the archived field leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_field_definitions('00000000-0000-4000-8000-000000000001', 'person', true)),
  current_setting('test.base')::integer + 1,
  'include_archived lists it again'
);
select throws_ok(
  format($$select better_supabase.set_field_value('00000000-0000-4000-8000-000000000001', 'contact', 'c-archive', %L, 'pro')$$,
    current_setting('test.def')),
  '55000', null, 'set_field_value refuses an archived field'
);
select throws_ok(
  $$select better_supabase.save_field_definition('00000000-0000-4000-8000-000000000001', 'person', 'archive_plan', 'Plan', 'text', false)$$,
  '55000', null, 'save_field_definition refuses an archived key'
);
select is(
  jsonb_array_length(better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-archive')),
  1,
  'the values of an archived field stay readable'
);

select better_supabase.archive_field_definition(current_setting('test.def')::uuid);
select is(pg_temp.n('field_definition.archived'), 1, 'archiving twice records one event');

select isnt(
  better_supabase.restore_field_definition(current_setting('test.def')::uuid) ->> 'archivedAt', 'x',
  'restoring succeeds'
);
select is(pg_temp.n('field_definition.restored'), 1, 'restoring records field_definition.restored');
select lives_ok(
  format($$select better_supabase.set_field_value('00000000-0000-4000-8000-000000000001', 'contact', 'c-archive', %L, 'pro')$$,
    current_setting('test.def')),
  'a restored field takes values again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  format('select better_supabase.archive_field_definition(%L)', current_setting('test.def')),
  '42501', null, 'another organization can''t archive the field'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.purge_field_definition(current_setting('test.def')::uuid), true,
  'purge removes the field'
);
select is(
  jsonb_array_length(better_supabase.read_field_values('00000000-0000-4000-8000-000000000001', 'contact', 'c-archive')),
  0,
  'purge takes the values with it'
);

select * from finish();
rollback;
