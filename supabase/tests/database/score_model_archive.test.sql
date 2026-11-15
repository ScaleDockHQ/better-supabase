-- Archiving a score model (ADR 1053): an archived model leaves list_score_models,
-- subject_scores and top_scores, compute_score and save_score_model refuse it,
-- its scores stay, restore brings it back, and purge is the hard delete behind
-- manage. Run with `supabase test db`.
begin;
select plan(20);

insert into better_supabase.automation_fields (subject_type, field_id, label, type, path, column_type)
values ('lead', 'employees', 'Employees', 'number', 'employees', 'integer');

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- The local stack may hold seeded models, so the lists are compared to this count.
select set_config('test.base',
  jsonb_array_length(better_supabase.list_score_models('00000000-0000-4000-8000-000000000001'))::text, true);

select set_config('test.model', better_supabase.save_score_model(
  '00000000-0000-4000-8000-000000000001',
  '{"key": "size", "name": "Size", "subjectType": "lead",
    "metrics": [{"id": "size", "source": "field", "field": "employees", "weight": 1, "cap": 100}],
    "bands": [{"label": "big", "min": 10}]}'
) ->> 'id', true);
select better_supabase.compute_score(
  '00000000-0000-4000-8000-000000000001', 'size', 'lead', 'l1', '{"employees": 20}'
);

select is(
  jsonb_array_length(better_supabase.list_score_models('00000000-0000-4000-8000-000000000001')), current_setting('test.base')::integer + 1,
  'the model is listed before an archive'
);

select isnt(
  better_supabase.archive_score_model(current_setting('test.model')::uuid) ->> 'archivedAt', null,
  'archiving sets archivedAt'
);
select is(pg_temp.n('score_model.archived'), 1, 'archiving records score_model.archived');
select is(
  jsonb_array_length(better_supabase.list_score_models('00000000-0000-4000-8000-000000000001')), current_setting('test.base')::integer,
  'the archived model leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_score_models('00000000-0000-4000-8000-000000000001', null, true)), current_setting('test.base')::integer + 1,
  'include_archived lists it again'
);
select is(
  jsonb_array_length(better_supabase.subject_scores('00000000-0000-4000-8000-000000000001', 'lead', 'l1')), 0,
  'subject_scores leaves its current score out'
);
select is(
  jsonb_array_length(better_supabase.top_scores('00000000-0000-4000-8000-000000000001', 'size')), 0,
  'top_scores leaves it out'
);
select is(
  jsonb_array_length(better_supabase.score_history('00000000-0000-4000-8000-000000000001', 'size', 'lead', 'l1')), 1,
  'score_history keeps the record of what was scored'
);
select isnt(
  better_supabase.get_score_model(current_setting('test.model')::uuid), null,
  'get_score_model still reads it by id'
);
select throws_ok(
  $$select better_supabase.compute_score('00000000-0000-4000-8000-000000000001', 'size', 'lead', 'l1', '{"employees": 30}')$$,
  '55000', null, 'compute_score refuses an archived model'
);
select throws_ok(
  format('select better_supabase.save_score_model(%L, %L)', '00000000-0000-4000-8000-000000000001',
    format('{"id": "%s", "name": "Renamed"}', current_setting('test.model'))),
  '55000', null, 'save_score_model refuses an archived model'
);

select better_supabase.archive_score_model(current_setting('test.model')::uuid);
select is(pg_temp.n('score_model.archived'), 1, 'archiving twice records one event');

select isnt(
  better_supabase.restore_score_model(current_setting('test.model')::uuid) ->> 'id', null,
  'restoring returns the model'
);
select is(pg_temp.n('score_model.restored'), 1, 'restoring records score_model.restored');
select is(
  jsonb_array_length(better_supabase.subject_scores('00000000-0000-4000-8000-000000000001', 'lead', 'l1')), 1,
  'the restored model shows its score again'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format('select better_supabase.archive_score_model(%L)', current_setting('test.model')),
  '42501', null, 'a member can''t archive a score model'
);
select throws_ok(
  format('select better_supabase.purge_score_model(%L)', current_setting('test.model')),
  '42501', null, 'a member can''t purge a score model'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select throws_ok(
  format('select better_supabase.restore_score_model(%L)', current_setting('test.model')),
  '42501', null, 'another organization can''t restore the model'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  better_supabase.purge_score_model(current_setting('test.model')::uuid), true,
  'purge removes the model'
);
select is(pg_temp.n('score_model.purged'), 1, 'purge records score_model.purged');

select * from finish();
rollback;
