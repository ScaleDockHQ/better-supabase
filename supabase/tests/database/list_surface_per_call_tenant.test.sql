-- The list functions that take the organization per call (ADR 0939):
-- list_hostnames, list_forms and list_access_requests as the admin (…00a1) and
-- the member (…00a2) of Acme (…0001), and for an organization neither is in.
begin;
select plan(12);

insert into better_supabase.hostnames (tenant_id, hostname, kind, verified_at, is_primary)
values
  ('00000000-0000-4000-8000-000000000001', 'app.acme-g6.test', 'custom', now(), true),
  ('00000000-0000-4000-8000-000000000001', 'beta.acme-g6.test', 'custom', null, false),
  ('00000000-0000-4000-8000-000000000002', 'app.initech-g6.test', 'custom', now(), true);

insert into better_supabase.access_requests (tenant_id, user_id, role, ended_at, created_at)
values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a1', 'admin', null, now() - interval '2 days'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'admin', now(), now() - interval '1 day'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'member', null, now());

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

-- Hostnames: the primary first, then a page, a count and a facet.
select is(
  (select jsonb_agg(h ->> 'hostname') from jsonb_array_elements(better_supabase.list_hostnames('00000000-0000-4000-8000-000000000001')) h),
  '["app.acme-g6.test", "beta.acme-g6.test"]'::jsonb,
  'list_hostnames keeps the primary first'
);
select is(
  better_supabase.list_hostnames('00000000-0000-4000-8000-000000000001', '{"count":true,"verified":["false"]}'::jsonb),
  '{"value":1,"exact":true}'::jsonb,
  'count honors the verified filter'
);
select is(
  (select jsonb_agg(h ->> 'hostname') from jsonb_array_elements(better_supabase.list_hostnames('00000000-0000-4000-8000-000000000001', '{"paged":true,"sort":"hostname","direction":"desc"}'::jsonb) -> 'items') h),
  '["beta.acme-g6.test", "app.acme-g6.test"]'::jsonb,
  'a page sorts by hostname, descending'
);
select is(
  better_supabase.list_hostnames('00000000-0000-4000-8000-000000000001', '{"facet":"verified"}'::jsonb) -> 'values' -> 0 -> 'count' ->> 'value',
  '1',
  'a facet counts the hostnames of each value'
);
select throws_ok(
  $$select better_supabase.list_hostnames('00000000-0000-4000-8000-000000000001', '{"sort":"nope"}'::jsonb)$$,
  '22023',
  null,
  'an undeclared sort is refused'
);
select throws_ok(
  $$select better_supabase.list_hostnames('00000000-0000-4000-8000-000000000099')$$,
  '42501',
  null,
  'another organization''s hostnames are forbidden'
);

-- Forms: a page by title and a status filter.
select lives_ok(
  $$select better_supabase.create_form('00000000-0000-4000-8000-000000000001', 'beta', 'Beta', null, '{}'::jsonb)$$,
  'the admin creates a form'
);
select lives_ok(
  $$select better_supabase.create_form('00000000-0000-4000-8000-000000000001', 'alpha', 'Alpha', null, '{}'::jsonb)$$,
  'the admin creates a second form'
);
select is(
  (select jsonb_agg(f ->> 'title') from jsonb_array_elements(better_supabase.list_forms('00000000-0000-4000-8000-000000000001', '{"paged":true,"sort":"title"}'::jsonb) -> 'items') f),
  '["Alpha", "Beta"]'::jsonb,
  'list_forms pages by title'
);

-- Access requests: the admin reads every request, the member only their own.
select is(
  better_supabase.list_access_requests('00000000-0000-4000-8000-000000000001', '{"count":true,"status":["ended"]}'::jsonb) ->> 'value',
  '1',
  'the derived status is a filter'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  better_supabase.list_access_requests('00000000-0000-4000-8000-000000000001', '{"count":true,"mine":true}'::jsonb) ->> 'value',
  '2',
  'mine keeps only the caller''s requests, even for a reader of the organization'
);
select is(
  (select r ->> 'role' from jsonb_array_elements(better_supabase.list_access_requests('00000000-0000-4000-8000-000000000001')) r limit 1),
  'member',
  'the newest request comes first'
);

select * from finish();
rollback;
