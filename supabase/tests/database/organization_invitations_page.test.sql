-- page_organization_invitations (ADR 0749, 0924): the open invitations as a
-- keyset page with a role filter, a text search, two sorts, facets and a count.
-- list_organization_invitations stays as it was. The admin owns Acme (…0001);
-- the member belongs to Acme only (supabase/seed.sql).
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.page_organization_invitations('00000000-0000-4000-8000-000000000001')$$,
  '42501',
  'Not allowed to list invitations',
  'a member cannot page the invitations'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.invite_member('00000000-0000-4000-8000-000000000001', 'zed@acme.test', 'admin')$$,
  'an owner invites an admin'
);

select is(
  (select jsonb_array_length(better_supabase.page_organization_invitations('00000000-0000-4000-8000-000000000001', '{"paged":true}') -> 'items')),
  (select count(*)::int from better_supabase.list_organization_invitations('00000000-0000-4000-8000-000000000001')),
  'the page holds the same open invitations as the list function'
);

select is(
  (select jsonb_agg(i ->> 'email')
   from jsonb_array_elements(better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"paged":true,"role":["member"]}'::jsonb) -> 'items') i),
  '["new@acme.test"]'::jsonb,
  'the role filter keeps the listed roles'
);

select is(
  (select jsonb_agg(i ->> 'email')
   from jsonb_array_elements(better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"paged":true,"search":"ZED@"}'::jsonb) -> 'items') i),
  '["zed@acme.test"]'::jsonb,
  'the search matches the email without regard to case'
);

select is(
  (select (better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"paged":true,"sort":"email","direction":"desc","limit":1}'::jsonb) -> 'items' -> 0 ->> 'email')),
  'zed@acme.test',
  'the email sort puts the last address first when descending'
);

select is(
  (select (better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"paged":true,"sort":"email","limit":1}'::jsonb) ->> 'hasMore')::boolean),
  true,
  'a page smaller than the list reports hasMore'
);

select ok(
  (select (better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"facet":"role"}'::jsonb)::text) like '%member%'),
  'the role facet counts the roles'
);

select is(
  (select better_supabase.page_organization_invitations(
     '00000000-0000-4000-8000-000000000001',
     '{"count":true,"role":["member"]}'::jsonb) ->> 'value')::int,
  1,
  'the count follows the same filters'
);

select throws_ok(
  $$select better_supabase.page_organization_invitations('00000000-0000-4000-8000-000000000001', '{"sort":"role"}')$$,
  '22023',
  null,
  'a sort the list does not declare is refused'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.page_organization_invitations('00000000-0000-4000-8000-000000000002')$$,
  '42501',
  'Not allowed to list invitations',
  'a plain member of another organization cannot page its invitations'
);

select * from finish();
rollback;
