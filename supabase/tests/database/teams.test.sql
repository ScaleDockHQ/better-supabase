-- team_ids_of(member) answers only for the caller, the service role and
-- direct database sessions. The admin (…00a1) and the member (…00a2) both
-- belong to Acme (…0001) (supabase/seed.sql).
begin;
select plan(5);

insert into better_supabase.teams (id, tenant_id, name, slug)
values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-000000000001', 'Support', 'support');
insert into better_supabase.team_members (team_id, user_id, tenant_id)
values ('00000000-0000-4000-8000-0000000000f1', '00000000-0000-4000-8000-0000000000a2', '00000000-0000-4000-8000-000000000001');

select is(
  (select count(*)::int from better_supabase.team_ids_of('00000000-0000-4000-8000-0000000000a2')),
  1,
  'a direct database session reads any user''s teams'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated"}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.team_ids_of('00000000-0000-4000-8000-0000000000a2')),
  1,
  'a member reads their own teams'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated"}',
  true
);

select throws_ok(
  $$select * from better_supabase.team_ids_of('00000000-0000-4000-8000-0000000000a2')$$,
  '42501',
  'team_ids_of reads only the caller''s teams',
  'a signed-in user cannot read another user''s teams'
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  (select count(*)::int from better_supabase.team_ids_of('00000000-0000-4000-8000-0000000000a2')),
  1,
  'the service role reads any user''s teams'
);

reset role;
select set_config('request.jwt.claims', '', true);

-- The email mirror stores the address lowercased.
update auth.users set email = 'Member.Mixed@Acme.Test'
where id = '00000000-0000-4000-8000-0000000000a2';
select is(
  (select email from better_supabase.profiles where id = '00000000-0000-4000-8000-0000000000a2'),
  'member.mixed@acme.test',
  'the profile mirrors the new email in lowercase'
);

select * from finish();
rollback;
