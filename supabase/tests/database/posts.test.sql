-- Posts on the fixture's access contract: the owner (…00a1) of Acme (…0001)
-- opens a feedback board, the member (…00a2) posts, replies and votes, the
-- owner locks, merges and moderates, and Globex (…0002) sees nothing.
begin;
select plan(22);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'board', (api.save_post_board('00000000-0000-4000-8000-000000000001',
  '{"key":"ideas","name":"Ideas","kind":"feedback"}') ->> 'id')::uuid;

select is(
  jsonb_array_length(api.list_post_boards('00000000-0000-4000-8000-000000000001')),
  1,
  'an owner opens a board'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select api.save_post_board('00000000-0000-4000-8000-000000000001', '{"key":"mine","name":"Mine"}')$$,
  '42501',
  null,
  'a member can''t manage boards'
);
select throws_ok(
  $$select api.create_post((select id from ids where name = 'board'), '{"title":"  "}')$$,
  '22023',
  null,
  'a post needs a title'
);

insert into ids
select 'dark', (api.create_post((select id from ids where name = 'board'), '{"title":"Dark mode","body":"Please"}') ->> 'id')::uuid;

select is(
  (select moderation_status from better_supabase.posts where id = (select id from ids where name = 'dark')),
  'visible',
  'a member''s post is published at once under post-moderation'
);
reset role;
select is(
  (select status from better_supabase.moderation_items where subject_type = 'post' and subject_id = (select id from ids where name = 'dark')::text),
  'visible',
  'the post is a moderation item'
);
set local role authenticated;
select is(
  api.vote_on_post((select id from ids where name = 'dark'), 1) ->> 'score',
  '1',
  'a member votes a post up'
);

select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'post',
  (select id from ids where name = 'dark')::text, 'Agreed');

select is(
  api.get_post((select id from ids where name = 'dark')) ->> 'replyCount',
  '1',
  'a comment on the post counts as a reply'
);

-- Acme owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  api.vote_on_post((select id from ids where name = 'dark'), 1) ->> 'score',
  '2',
  'votes add up'
);
select is(
  api.set_post_state((select id from ids where name = 'dark'), '{"status":"planned","locked":true}') ->> 'status',
  'planned',
  'a moderator sets the status and locks the replies'
);
select throws_ok(
  $$select api.set_post_state((select id from ids where name = 'dark'), '{"status":"shipped"}')$$,
  '22023',
  null,
  'a status is one of the known ones'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select better_supabase.create_comment('00000000-0000-4000-8000-000000000001', 'post',
    (select id from ids where name = 'dark')::text, 'Me too')$$,
  '42501',
  null,
  'a locked post takes no replies'
);
select throws_ok(
  $$select api.update_post((select id from ids where name = 'dark'), '{"title":"Dark theme"}')$$,
  '42501',
  null,
  'the author can''t edit a locked post'
);
select throws_ok(
  $$select api.set_post_state((select id from ids where name = 'dark'), '{"pinned":true}')$$,
  '42501',
  null,
  'a member can''t moderate posts'
);

insert into ids
select 'night', (api.create_post((select id from ids where name = 'board'), '{"title":"Night theme"}') ->> 'id')::uuid;
select api.vote_on_post((select id from ids where name = 'night'), 1);

-- Acme owner merges the duplicate.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  api.merge_posts((select id from ids where name = 'night'), (select id from ids where name = 'dark')) -> 'votes' ->> 'score',
  '2',
  'merging keeps one vote per voter on the target'
);
select is(
  (select status || ':' || (merged_into_id = (select id from ids where name = 'dark'))::text
    from better_supabase.posts where id = (select id from ids where name = 'night')),
  'closed:true',
  'the duplicate closes and points at the target'
);
select throws_ok(
  $$select api.vote_on_post((select id from ids where name = 'night'), 1)$$,
  '42501',
  null,
  'a merged post takes no votes'
);
select is(
  jsonb_array_length(api.list_posts('00000000-0000-4000-8000-000000000001', '{"sort":"top"}')),
  1,
  'merged posts stay out of the list'
);

reset role;
insert into ids
select 'item', id from better_supabase.moderation_items
where subject_type = 'post' and subject_id = (select id from ids where name = 'dark')::text;
set local role authenticated;

select api.moderate((select id from ids where name = 'item'), 'hide', 'off topic');

select is(
  (select moderation_status from better_supabase.posts where id = (select id from ids where name = 'dark')),
  'hidden',
  'hiding the moderation item hides the post'
);

-- Acme member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select throws_ok(
  $$select api.vote_on_post((select id from ids where name = 'dark'), -1)$$,
  'P0002',
  null,
  'a hidden post takes no votes'
);

-- Globex owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  api.list_posts('00000000-0000-4000-8000-000000000001', '{"merged":true}'),
  '[]'::jsonb,
  'another organization reads no posts'
);

-- Acme owner bans the member.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select better_supabase.ban_user('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', 'spam');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  $$select api.create_post((select id from ids where name = 'board'), '{"title":"Again"}')$$,
  '42501',
  null,
  'a banned member can''t post'
);
select is(
  api.delete_post((select id from ids where name = 'night')),
  true,
  'the author deletes their post'
);

select * from finish();
rollback;
