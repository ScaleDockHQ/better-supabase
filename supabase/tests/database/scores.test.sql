-- The scores module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) saves a lead model and scores a lead, the member (…00a2)
-- reads the score but can't change the model, and Globex (…0002) sees
-- nothing.
begin;
select plan(12);

insert into better_supabase.rule_fields (subject_type, field_id, label, type, path, column_type)
values
  ('lead', 'stage', 'Stage', 'select', 'stage', 'text'),
  ('lead', 'employees', 'Employees', 'number', 'employees', 'integer');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.model', better_supabase.save_score_model(
  '00000000-0000-4000-8000-000000000001',
  '{
    "key": "lead",
    "name": "Lead score",
    "subjectType": "lead",
    "rules": [{
      "id": "qualified",
      "points": 20,
      "conditions": {"id": "g", "type": "group", "combinator": "and", "rules": [
        {"id": "r", "type": "rule", "path": ["stage"], "operator": "is", "value": "qualified"}
      ]}
    }],
    "metrics": [{"id": "size", "source": "field", "field": "employees", "weight": 0.5, "cap": 25}],
    "bands": [{"label": "warm", "min": 20}, {"label": "hot", "min": 40}]
  }'
) ->> 'id', true);

select is(
  (better_supabase.get_score_model(current_setting('test.model')::uuid) -> 'bands' -> 0 ->> 'label'),
  'hot',
  'bands are stored highest min first'
);
select throws_ok(
  $$select better_supabase.save_score_model('00000000-0000-4000-8000-000000000001', '{"key": "lead", "name": "Again", "subjectType": "lead"}')$$,
  '23505',
  null,
  'a model key is unique in the organization'
);
select throws_ok(
  $$select better_supabase.save_score_model('00000000-0000-4000-8000-000000000001', '{"key": "bad", "name": "Bad", "subjectType": "lead", "metrics": [{"id": "m", "source": "field", "field": "stage"}]}')$$,
  '22023',
  null,
  'a field metric names a number field'
);

select is(
  (better_supabase.compute_score(
    '00000000-0000-4000-8000-000000000001', 'lead', 'lead', 'l1',
    '{"stage": "qualified", "employees": 30}'
  ) - 'id' - 'computedAt' - 'organizationId' - 'modelId' - 'breakdown'),
  jsonb_build_object(
    'modelKey', 'lead', 'modelVersion', 1, 'subjectType', 'lead', 'subjectId', 'l1',
    'score', 35, 'band', 'warm', 'current', true, 'changed', true
  ),
  'a lead scores rule points plus capped metric points, with its band'
);
select is(
  (better_supabase.compute_score(
    '00000000-0000-4000-8000-000000000001', 'lead', 'lead', 'l1',
    '{"stage": "qualified", "employees": 30}'
  ) ->> 'changed')::boolean,
  false,
  'an unchanged score is not saved again'
);
select is(
  (better_supabase.compute_score(
    '00000000-0000-4000-8000-000000000001', 'lead', 'lead', 'l1',
    '{"stage": "qualified", "employees": 900}'
  ) ->> 'band'),
  'hot',
  'a new score replaces the current one'
);
select is(
  (select count(*)::integer from better_supabase.scores where subject_id = 'l1'),
  2,
  'the old score stays as history'
);
reset role;
select is(
  (select count(*)::integer from better_supabase.outbox_events where type = 'score.changed' and payload ->> 'subjectId' = 'l1'),
  2,
  'each change emits score.changed'
);
set local role authenticated;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  jsonb_array_length(better_supabase.subject_scores('00000000-0000-4000-8000-000000000001', 'lead', 'l1')),
  1,
  'a member reads a record''s current scores'
);
select throws_ok(
  $$select better_supabase.save_score_model('00000000-0000-4000-8000-000000000001', '{"key": "mine", "name": "Mine", "subjectType": "lead"}')$$,
  '42501',
  null,
  'a member can''t manage score models'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*)::integer from better_supabase.scores),
  0,
  'another organization reads no scores'
);
select throws_ok(
  $$select better_supabase.top_scores('00000000-0000-4000-8000-000000000001', 'lead')$$,
  '42501',
  null,
  'another organization can''t list the top scores'
);

select * from finish();
rollback;
