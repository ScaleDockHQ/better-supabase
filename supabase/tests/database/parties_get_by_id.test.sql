-- get_company and get_person read one active party by id as the caller (the
-- plan before: loadContact paged list_companies). The Acme member (…a2) reads
-- both, an archived or missing id gives null, and the Globex owner (…a3) sees
-- nothing. Run with `supabase test db`.
begin;
select plan(7);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;
insert into ids values
  ('company', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null, '{"name": "By id Co"}') ->> 'id')::uuid),
  ('person', (better_supabase.save_person('00000000-0000-4000-8000-000000000001', null, '{"name": "By id Person"}') ->> 'id')::uuid);

select is(
  better_supabase.get_company((select id from ids where name = 'company')) ->> 'name',
  'By id Co',
  'a member reads a company by id'
);
select is(
  better_supabase.get_person((select id from ids where name = 'person')) ->> 'name',
  'By id Person',
  'a member reads a person by id'
);
select is(
  better_supabase.get_company('00000000-0000-4000-8000-00000000ffff'),
  null::jsonb,
  'an unknown id gives null'
);
select is(
  better_supabase.get_company((select id from ids where name = 'person')),
  null::jsonb,
  'a person id is not a company'
);

select better_supabase.archive_company((select id from ids where name = 'company'), true);
select is(
  better_supabase.get_company((select id from ids where name = 'company')),
  null::jsonb,
  'an archived company gives null, as the list does'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  better_supabase.get_person((select id from ids where name = 'person')),
  null::jsonb,
  'another organization does not read the person'
);

reset role;
select ok(
  (select p.provolatile = 's' from pg_proc p where p.oid = 'better_supabase.get_company(uuid)'::regprocedure),
  'the read is stable'
);

select * from finish();
rollback;
