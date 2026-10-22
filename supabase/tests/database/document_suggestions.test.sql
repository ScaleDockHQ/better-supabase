-- Document suggestions and named versions on the fixture's access contract.
-- Ann (…a1) owns Acme (…0001) and Ben (…a2) is a member; Carl (…a3) owns
-- Globex (…0002) and is not an Acme member (supabase/seed.sql).
begin;
select plan(10);

select has_table('better_supabase', 'document_suggestions', 'the suggestions table exists');
select ok(
  not has_table_privilege('authenticated', 'better_supabase.document_suggestions', 'select'),
  'suggestions are read through the functions only'
);

-- Acme owner opens the document.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  'test.document',
  api.open_document('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001') ->> 'id',
  true
);

-- Acme member suggests a change.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select set_config(
  'test.suggestion',
  api.suggest_document_change(current_setting('test.document')::uuid, 'AQI=', 'Fix a typo') ->> 'id',
  true
);
select is(
  api.list_document_suggestions(current_setting('test.document')::uuid) -> 0 ->> 'summary',
  'Fix a typo',
  'a member suggests a change'
);

-- Back to the owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_like(
  $$ select api.decide_document_suggestion(current_setting('test.suggestion')::uuid, 'withdrawn') $$,
  '%only the author%',
  'only the author withdraws a suggestion'
);
select ok(
  (api.decide_document_suggestion(current_setting('test.suggestion')::uuid, 'accepted') ->> 'seq') is not null,
  'accepting appends the suggestion to the log'
);
select throws_like(
  $$ select api.decide_document_suggestion(current_setting('test.suggestion')::uuid, 'rejected') $$,
  '%already decided%',
  'a decided suggestion stays decided'
);
select is(
  jsonb_array_length(api.list_document_suggestions(current_setting('test.document')::uuid, 'all')),
  1,
  'the decided suggestion is listed with status all'
);

select set_config(
  'test.version',
  api.save_document_version(current_setting('test.document')::uuid, 'AQI=') ->> 'id',
  true
);
select ok(
  api.name_document_version(current_setting('test.document')::uuid, current_setting('test.version')::uuid, 'Approved'),
  'an editor names a version'
);
select is(
  api.list_document_versions(current_setting('test.document')::uuid) -> 0 ->> 'label',
  'Approved',
  'the version keeps its name'
);

-- Globex owner, outside Acme.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select throws_like(
  $$ select api.suggest_document_change(current_setting('test.document')::uuid, 'AQI=') $$,
  '%not found%',
  'an outsider cannot suggest changes'
);

select * from finish();
rollback;
