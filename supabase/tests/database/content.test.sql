-- The content module with its default options (types page and post, locale
-- en, no approval) against the seed: the Acme owner (…a1) publishes, the Acme
-- member (…a2) writes drafts, Globex (…a3) sees nothing of Acme's, and anon
-- reads only published entries through public_content_entry and
-- public_content_entries. Run with `supabase test db`.
begin;
select plan(21);

select is(
  (select rowsecurity from pg_catalog.pg_tables
   where schemaname = 'better_supabase' and tablename = 'content_entries'),
  true,
  'content_entries has RLS enabled'
);
select table_privs_are('better_supabase', 'content_entries', 'anon', '{}'::text[],
  'anon has no privileges on content entries');
select is(
  (select array_agg(distinct p.proname::text order by p.proname::text)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('api', 'better_supabase')
     and has_function_privilege('anon', p.oid, 'execute')
     and p.proname ~ 'content_entr'),
  array['public_content_entries', 'public_content_entry'],
  'anon can execute the two public reads and no other content function'
);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

-- Acme member: writes drafts but can't publish.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

insert into ids
select 'about', (better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
  '{"type":"page","slug":"about","title":"About us","body":{"type":"doc","content":[]}}') ->> 'id')::uuid;

select is(
  (select status from better_supabase.content_entries where id = (select id from ids where name = 'about')),
  'draft',
  'a new entry is a draft'
);
select throws_ok(
  $$select better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
    '{"type":"page","slug":"about","title":"Another about"}')$$,
  '23505',
  null,
  'a slug is unique per organization, type and locale'
);
select lives_ok(
  $$select better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
    '{"type":"post","slug":"about","title":"About this blog"}')$$,
  'another type may reuse the slug'
);
select throws_ok(
  $$select better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
    '{"type":"recipe","slug":"soup","title":"Soup"}')$$,
  '22023',
  null,
  'a type is one of options.types'
);
select throws_ok(
  $$select better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
    '{"type":"page","slug":"Not A Slug","title":"Bad"}')$$,
  '22023',
  null,
  'a slug is lowercase words joined by - or /'
);
select throws_ok(
  $$select better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
    '{"type":"page","locale":"fr","slug":"a-propos","title":"A propos"}')$$,
  '22023',
  null,
  'a locale is one of options.locales'
);
select is(
  better_supabase.update_content_entry((select id from ids where name = 'about'), '{"title":"About Acme"}') ->> 'title',
  'About Acme',
  'a writer edits a draft'
);
select throws_ok(
  $$select better_supabase.publish_content_entry((select id from ids where name = 'about'))$$,
  '42501',
  null,
  'a member can''t publish'
);
select throws_ok(
  $$select better_supabase.schedule_content_entry((select id from ids where name = 'about'), now() + interval '1 day')$$,
  '42501',
  null,
  'a member can''t schedule'
);

-- Acme owner: publishes one entry and schedules another.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);

select is(
  better_supabase.publish_content_entry((select id from ids where name = 'about')) ->> 'status',
  'published',
  'an owner publishes an entry'
);

insert into ids
select 'launch', (better_supabase.create_content_entry('00000000-0000-4000-8000-000000000001',
  '{"type":"post","slug":"launch","title":"We launched"}') ->> 'id')::uuid;

select throws_ok(
  $$select better_supabase.schedule_content_entry((select id from ids where name = 'launch'), now() - interval '1 hour')$$,
  '22023',
  null,
  'a publish time is in the future'
);
select is(
  better_supabase.schedule_content_entry((select id from ids where name = 'launch'), now() + interval '1 hour') ->> 'status',
  'scheduled',
  'an owner schedules an entry'
);

-- Globex owner.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);

select is(
  better_supabase.get_content_entry((select id from ids where name = 'about')),
  null,
  'another organization can''t read the entry'
);
select throws_ok(
  $$select better_supabase.update_content_entry((select id from ids where name = 'about'), '{"title":"Hijack"}')$$,
  '42501',
  null,
  'another organization can''t edit the entry'
);

-- The scheduler publishes the entry once its time has passed.
reset role;
update better_supabase.content_entries
  set publish_at = now() - interval '1 minute'
  where id = (select id from ids where name = 'launch');
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select is(
  better_supabase.publish_due_content_entries(),
  1,
  'the scheduler publishes the due entry'
);

-- Anon reads published entries only.
reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select is(
  better_supabase.public_content_entry('00000000-0000-4000-8000-000000000001', 'page', 'about') ->> 'title',
  'About Acme',
  'anon reads a published entry by slug'
);
select is(
  better_supabase.public_content_entry('00000000-0000-4000-8000-000000000001', 'post', 'about'),
  null,
  'anon can''t read a draft'
);
select is(
  (select jsonb_path_query_array(
    better_supabase.public_content_entries('00000000-0000-4000-8000-000000000001', 'post'),
    '$[*].slug')),
  '["launch"]'::jsonb,
  'anon lists the published posts'
);

select * from finish();
rollback;
