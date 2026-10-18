-- The tags block on the fixture's access contract, for the tag input on the
-- customer page. Acme (…0001) has the seeded VIP and Churn risk tags, and
-- Road Runner Inc (…a001) carries VIP (supabase/seed.sql). Members read and
-- apply tags; only admins and owners create them.
begin;
select plan(9);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select jsonb_agg(tag ->> 'name') from jsonb_array_elements(api.list_tags('00000000-0000-4000-8000-000000000001', 'customer')) as tag),
  '["VIP", "Churn risk"]'::jsonb,
  'a member lists the customer tags in rank order'
);
select is(
  (select jsonb_agg(tag ->> 'name') from jsonb_array_elements(api.subject_tags('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001')) as tag),
  '["VIP"]'::jsonb,
  'a member reads a customer''s tags'
);
select ok(
  api.tag('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001', '00000000-0000-4000-8000-00000000b102'),
  'a member tags a customer they can read'
);
select is(
  jsonb_array_length(api.subject_tags('00000000-0000-4000-8000-000000000001', 'customer', '00000000-0000-4000-8000-00000000a001')),
  2,
  'the customer carries both tags'
);
select throws_ok(
  $$select api.create_tag('00000000-0000-4000-8000-000000000001', 'customer', 'Partner', null, null)$$,
  '42501',
  'not allowed to manage tags',
  'a member cannot create a tag'
);
select throws_ok(
  $$select api.list_tags('00000000-0000-4000-8000-000000000002', null)$$,
  '42501',
  'not allowed to read tags',
  'a member of Acme cannot list Globex tags'
);
select throws_ok(
  $$select api.tag('00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', '00000000-0000-4000-8000-00000000b102')$$,
  '42501',
  'not allowed to apply tags',
  'a member of Acme cannot tag a Globex customer'
);
select throws_ok(
  $$select api.untag('00000000-0000-4000-8000-000000000002', 'customer', '00000000-0000-4000-8000-00000000a003', '00000000-0000-4000-8000-00000000b102')$$,
  '42501',
  'not allowed to apply tags',
  'nor untag one'
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
  (api.create_tag('00000000-0000-4000-8000-000000000001', 'customer', 'Partner', null, null) ->> 'slug'),
  'partner',
  'the owner creates a tag'
);

select * from finish();
rollback;
