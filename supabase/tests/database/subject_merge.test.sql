-- Merging two companies of Acme (…0001) through merge_companies moves what
-- other blocks hang on the dropped company to the kept one: comments, tags,
-- reactions, relations and guest grants. A row the kept company already has
-- under the same key goes instead of turning into a duplicate, and a relation
-- between the two goes. The member (…00a2) may not merge.
begin;
select plan(13);

insert into better_supabase.companies (id, tenant_id, name, lifecycle) values
  ('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-000000000001', 'Acme Keep', 'lead'),
  ('00000000-0000-4000-8000-00000000c002', '00000000-0000-4000-8000-000000000001', 'Acme Drop', 'lead'),
  ('00000000-0000-4000-8000-00000000c003', '00000000-0000-4000-8000-000000000001', 'Partner', 'lead');

insert into better_supabase.comments (organization_id, subject_type, subject_id, body) values
  ('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000c002', 'on drop'),
  ('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000c002', 'also on drop');

insert into better_supabase.tags (id, tenant_id, kind, name, slug) values
  ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'default', 'VIP', 'vip'),
  ('00000000-0000-4000-8000-00000000d002', '00000000-0000-4000-8000-000000000001', 'default', 'Churn risk', 'churn-risk');
insert into better_supabase.taggings (tenant_id, tag_id, subject_type, subject_id) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d001', 'company', '00000000-0000-4000-8000-00000000c001'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d001', 'company', '00000000-0000-4000-8000-00000000c002'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000d002', 'company', '00000000-0000-4000-8000-00000000c002');

insert into better_supabase.reactions (tenant_id, subject_type, subject_id, actor, emoji) values
  ('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000c001', 'a1', 'thumbsup'),
  ('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000c002', 'a1', 'thumbsup'),
  ('00000000-0000-4000-8000-000000000001', 'company', '00000000-0000-4000-8000-00000000c002', 'a1', 'eyes');

-- relates is symmetric: the smaller end is stored first.
insert into better_supabase.relations (tenant_id, kind, source_type, source_id, target_type, target_id) values
  ('00000000-0000-4000-8000-000000000001', 'relates', 'company', '00000000-0000-4000-8000-00000000c001', 'company', '00000000-0000-4000-8000-00000000c002'),
  ('00000000-0000-4000-8000-000000000001', 'relates', 'company', '00000000-0000-4000-8000-00000000c002', 'company', '00000000-0000-4000-8000-00000000c003'),
  ('00000000-0000-4000-8000-000000000001', 'blocks', 'company', '00000000-0000-4000-8000-00000000c003', 'company', '00000000-0000-4000-8000-00000000c002');

insert into better_supabase.guests (id, tenant_id, email, name, status) values
  ('00000000-0000-4000-8000-00000000e001', '00000000-0000-4000-8000-000000000001', 'client@example.test', 'Client', 'invited');
insert into better_supabase.guest_grants (tenant_id, guest_id, subject_type, subject_id, actions) values
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000e001', 'company', '00000000-0000-4000-8000-00000000c001', '{read}'),
  ('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000e001', 'company', '00000000-0000-4000-8000-00000000c002', '{read}');

-- The member may not merge.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.merge_companies('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000c002')$$,
  '42501',
  'not allowed to change companies and people',
  'a member without parties.manage cannot merge'
);
select throws_ok(
  $$select better_supabase.merge_subject_refs('better_supabase.companies', '00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000c002')$$,
  '42501',
  null,
  'signed-in users cannot call the dispatcher'
);

-- The admin merges.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.merge_companies('00000000-0000-4000-8000-00000000c001', '00000000-0000-4000-8000-00000000c002') ->> 'id',
  '00000000-0000-4000-8000-00000000c001',
  'merge_companies returns the kept company'
);

reset role;

select is(
  (select merged_into::text from better_supabase.companies where id = '00000000-0000-4000-8000-00000000c002'),
  '00000000-0000-4000-8000-00000000c001',
  'the dropped company points at the kept one'
);
select is(
  (select count(*)::integer from better_supabase.comments where subject_type = 'company' and subject_id = '00000000-0000-4000-8000-00000000c001'),
  2,
  'the comments move to the kept company'
);
select is(
  (select count(*)::integer from better_supabase.comments where subject_id = '00000000-0000-4000-8000-00000000c002'),
  0,
  'no comment stays on the dropped company'
);
select results_eq(
  $$select tag_id::text from better_supabase.taggings where subject_id = '00000000-0000-4000-8000-00000000c001' order by tag_id$$,
  $$values ('00000000-0000-4000-8000-00000000d001'::text), ('00000000-0000-4000-8000-00000000d002'::text)$$,
  'tags move, and a tag both had stays once'
);
select results_eq(
  $$select emoji from better_supabase.reactions where subject_id = '00000000-0000-4000-8000-00000000c001' order by emoji$$,
  $$values ('eyes'::text), ('thumbsup'::text)$$,
  'reactions move, and a reaction both had stays once'
);
select is(
  (select count(*)::integer from better_supabase.relations where '00000000-0000-4000-8000-00000000c002' in (source_id, target_id)),
  0,
  'no relation names the dropped company'
);
select is(
  (select count(*)::integer from better_supabase.relations where kind = 'relates' and source_id = '00000000-0000-4000-8000-00000000c001' and target_id = '00000000-0000-4000-8000-00000000c001'),
  0,
  'the relation between the two goes'
);
select results_eq(
  $$select kind, source_id, target_id from better_supabase.relations order by kind$$,
  $$values
    ('blocks'::text, '00000000-0000-4000-8000-00000000c003'::text, '00000000-0000-4000-8000-00000000c001'::text),
    ('relates'::text, '00000000-0000-4000-8000-00000000c001'::text, '00000000-0000-4000-8000-00000000c003'::text)$$,
  'the other relations point at the kept company'
);
select is(
  (select count(*)::integer from better_supabase.guest_grants where subject_type = 'company' and subject_id = '00000000-0000-4000-8000-00000000c001'),
  1,
  'a guest granted both keeps one grant on the kept company'
);
select is(
  (select count(*)::integer from better_supabase.guest_grants where subject_id = '00000000-0000-4000-8000-00000000c002'),
  0,
  'no grant stays on the dropped company'
);

select * from finish();
rollback;
