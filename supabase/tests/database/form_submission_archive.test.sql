-- Archiving a form submission (ADR 1051): an archived submission leaves
-- list_form_submissions and form_nps, restore brings it back, a draft is
-- refused, and purge is the hard delete. Run with `supabase test db`.
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

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values ('form', (better_supabase.create_form(
  '00000000-0000-4000-8000-000000000001', 'archive-form', 'Archive form') ->> 'id')::uuid);
select better_supabase.publish_form_version(
  (select id from ids where name = 'form'),
  '{"steps": [{"key": "main", "title": "Main", "fields": [{"key": "score", "label": "Score", "type": "nps"}]}]}'::jsonb
);
select better_supabase.update_form((select id from ids where name = 'form'), null, null, 'open');

insert into ids values ('kept', (better_supabase.submit_form((select id from ids where name = 'form'), '{"score": 9}'::jsonb) ->> 'id')::uuid);
insert into ids values ('gone', (better_supabase.submit_form((select id from ids where name = 'form'), '{"score": 2}'::jsonb) ->> 'id')::uuid);
insert into ids values ('draft', (better_supabase.submit_form((select id from ids where name = 'form'), '{"score": 5}'::jsonb, null, null, null, true) ->> 'id')::uuid);

select is(
  jsonb_array_length(better_supabase.list_form_submissions((select id from ids where name = 'form'))), 3,
  'every submission is listed before an archive'
);
select is(
  (better_supabase.form_nps((select id from ids where name = 'form')) ->> 'responses')::integer, 2,
  'form_nps counts the two submitted answers'
);

select isnt(
  better_supabase.archive_form_submission((select id from ids where name = 'gone')) ->> 'archivedAt', null,
  'archiving sets archivedAt'
);
select is(pg_temp.n('form_submission.archived'), 1, 'archiving records form_submission.archived');
select is(
  jsonb_array_length(better_supabase.list_form_submissions((select id from ids where name = 'form'))), 2,
  'the archived submission leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_form_submissions((select id from ids where name = 'form'), null, 50, null, true)), 3,
  'include_archived lists it again'
);
select is(
  (better_supabase.form_nps((select id from ids where name = 'form')) ->> 'responses')::integer, 1,
  'form_nps leaves the archived answer out'
);
select is(
  better_supabase.get_form_submission((select id from ids where name = 'gone')) ->> 'id',
  (select id::text from ids where name = 'gone'),
  'get_form_submission still reads it by id'
);

select better_supabase.archive_form_submission((select id from ids where name = 'gone'));
select is(pg_temp.n('form_submission.archived'), 1, 'archiving twice records one event');
select throws_ok(
  format('select better_supabase.archive_form_submission(%L)', (select id from ids where name = 'draft')),
  '55000', null, 'a draft is refused'
);

select isnt(
  better_supabase.restore_form_submission((select id from ids where name = 'gone')) ->> 'id', null,
  'restoring returns the submission'
);
select is(
  jsonb_array_length(better_supabase.list_form_submissions((select id from ids where name = 'form'))), 3,
  'the restored submission is listed again'
);

select is(
  better_supabase.purge_form_submission((select id from ids where name = 'gone')), true,
  'purge removes the row'
);
select is(pg_temp.n('form_submission.purged'), 1, 'purge records form_submission.purged');

select * from finish();
rollback;
