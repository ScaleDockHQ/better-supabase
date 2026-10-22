-- my_permissions and subject_titles on the fixture's access contract, for
-- `<Can>` and the SubjectLink recipe. Acme (…0001) owns Road Runner Inc
-- (…a001) and Globex (…0002) owns Initech (…a003) (supabase/seed.sql).
begin;
select plan(8);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.my_permissions('00000000-0000-4000-8000-000000000001', array['customers.read', 'members.remove', 'customers.read']),
  array['customers.read'],
  'a member holds the keys can() grants, once each'
);
select ok(
  'customers.read' = any(api.my_permissions('00000000-0000-4000-8000-000000000001')),
  'without keys, a member gets the role''s list'
);
select is(
  api.my_permissions('00000000-0000-4000-8000-000000000002', array['customers.read']),
  '{}'::text[],
  'a member of Acme holds nothing in Globex'
);
select is(
  api.subject_titles('[{"type":"customer","id":"00000000-0000-4000-8000-00000000a001"},{"type":"customer","id":"00000000-0000-4000-8000-00000000a003"},{"type":"nope","id":"x"}]'),
  '[{"type":"customer","id":"00000000-0000-4000-8000-00000000a001","title":"Road Runner Inc","url":"/customers/00000000-0000-4000-8000-00000000a001"}]'::jsonb,
  'subject_titles returns the readable subjects with title and path, and skips the rest'
);
select is(
  api.subject_titles('[]'),
  '[]'::jsonb,
  'no refs, no titles'
);
select throws_ok(
  $$select api.subject_titles('{"type":"customer"}')$$,
  '22023',
  'refs must be a JSON array of { type, id }',
  'refs must be an array'
);

-- Acme owner.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  api.my_permissions('00000000-0000-4000-8000-000000000001'),
  array['*'],
  'an owner holds the wildcard'
);

-- Anonymous.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  better_supabase.my_permissions('00000000-0000-4000-8000-000000000001', array['customers.read']),
  '{}'::text[],
  'an anonymous caller holds nothing'
);

select * from finish();
rollback;
