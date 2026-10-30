-- Lead scoring on the fixture's access contract: the owner (…00a1) of Acme
-- (…0001) saves the "lead" model over people and scores a person, a change
-- to the person marks them for the next run, the member (…00a2) can't score
-- and Globex (…0002) reads nothing.
begin;
select plan(13);

insert into better_supabase.automation_fields (subject_type, field_id, label, type, path, column_type)
values
  ('person', 'lifecycle', 'Lifecycle', 'select', 'lifecycle', 'text'),
  ('person', 'mail.sent', 'Emails sent', 'number', 'mail.sent', 'integer');

insert into better_supabase.people (id, tenant_id, name, email, lifecycle)
values ('00000000-0000-4000-8000-00000000f201', '00000000-0000-4000-8000-000000000001', 'Dee Lead', 'dee@lead.test', 'lead');

select is(
  (select stale from better_supabase.lead_score_checks where subject_id = '00000000-0000-4000-8000-00000000f201'),
  true,
  'a new person is marked for scoring'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select better_supabase.save_score_model('00000000-0000-4000-8000-000000000001', '{
  "key": "lead",
  "name": "Lead score",
  "subjectType": "person",
  "rules": [{
    "id": "lead",
    "points": 10,
    "conditions": {"id": "g", "type": "group", "combinator": "and", "rules": [
      {"id": "r", "type": "rule", "path": ["lifecycle"], "operator": "is", "value": "lead"}
    ]}
  }],
  "metrics": [{"id": "sent", "source": "field", "field": "mail.sent", "weight": 5}],
  "bands": [{"label": "warm", "min": 10}]
}');

select is(
  api.lead_fields('00000000-0000-4000-8000-000000000001', 'person', '00000000-0000-4000-8000-00000000f201') -> 'mail' ->> 'sent',
  '0',
  'the lead fields carry the person''s mail counts'
);
select is(
  api.lead_fields('00000000-0000-4000-8000-000000000001', 'person', '00000000-0000-4000-8000-00000000f201') -> 'segments',
  '[]'::jsonb,
  'the lead fields carry the person''s segments'
);
select is(
  api.lead_fields('00000000-0000-4000-8000-000000000001', 'person', 'not-a-uuid'),
  null,
  'an id that names no person has no lead fields'
);
select is(
  (api.score_lead('00000000-0000-4000-8000-000000000001', 'person', '00000000-0000-4000-8000-00000000f201') - 'id' - 'computedAt' - 'modelId' - 'breakdown' - 'organizationId'),
  jsonb_build_object(
    'modelKey', 'lead', 'modelVersion', 1, 'subjectType', 'person',
    'subjectId', '00000000-0000-4000-8000-00000000f201',
    'score', 10, 'band', 'warm', 'current', true, 'changed', true
  ),
  'an owner scores a person under the lead model'
);
select is(
  (select stale from better_supabase.lead_score_checks where subject_id = '00000000-0000-4000-8000-00000000f201'),
  false,
  'a scored person is fresh'
);
select throws_ok(
  $$select api.score_lead('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000f201')$$,
  '22023',
  null,
  'only people are lead-scored'
);
select throws_ok(
  $$select api.score_lead('00000000-0000-4000-8000-000000000001', 'person', '00000000-0000-4000-8000-00000000ffff')$$,
  'P0002',
  null,
  'scoring a missing person fails'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select api.score_lead('00000000-0000-4000-8000-000000000001', 'person', '00000000-0000-4000-8000-00000000f201')$$,
  '42501',
  null,
  'a member can''t score leads'
);
select throws_ok(
  $$select api.score_leads_due(10)$$,
  '42501',
  null,
  'only the service role runs the rescoring'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*)::integer from better_supabase.lead_score_checks where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0,
  'another organization reads no checks'
);

reset role;
update better_supabase.people set lifecycle = 'customer' where id = '00000000-0000-4000-8000-00000000f201';
select is(
  (select stale from better_supabase.lead_score_checks where subject_id = '00000000-0000-4000-8000-00000000f201'),
  true,
  'a changed person is marked for scoring again'
);

select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select api.score_leads_due(1000);
reset role;

select is(
  (select s.score::numeric from better_supabase.scores s
    where s.subject_id = '00000000-0000-4000-8000-00000000f201' and s.is_current),
  0::numeric,
  'the rescoring run scores the changed person again'
);

select * from finish();
rollback;
