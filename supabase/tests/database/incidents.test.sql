-- The incidents module and its anonymous status page against the seed: the
-- Acme owner (…a1) runs incidents for Acme (…001), the Globex owner (…a3) for
-- Globex (…002), and anon reads only public_status_page. Run with
-- `supabase test db`.
begin;
select plan(23);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('incidents', 'incident_updates', 'incident_impacts', 'incident_postmortems',
       'incident_status_components', 'incident_status_component_history', 'incident_status_pages')
     and rowsecurity),
  7::bigint,
  'every incidents table has RLS enabled'
);
select table_privs_are('better_supabase', 'incidents', 'anon', '{}'::text[],
  'anon has no privileges on incidents');
select table_privs_are('better_supabase', 'incident_updates', 'anon', '{}'::text[],
  'anon has no privileges on incident updates');
select table_privs_are('better_supabase', 'incident_status_components', 'anon', '{}'::text[],
  'anon has no privileges on status components');
select table_privs_are('better_supabase', 'incident_status_pages', 'anon', '{}'::text[],
  'anon has no privileges on status pages');
select is(
  (select array_agg(p.proname::text order by p.proname)
   from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname in ('api', 'better_supabase')
     and has_function_privilege('anon', p.oid, 'execute')
     and p.proname ~ '(incident|status_page|status_component|postmortem)'),
  array['public_status_page', 'public_status_page'],
  'anon can execute public_status_page and no other incidents function'
);

-- Acme: a public component, a private one, a published page, a public incident
-- with a private note, and a private incident.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
insert into ids values
  ('api', (better_supabase.save_status_component('00000000-0000-4000-8000-000000000001', 'API') ->> 'id')::uuid),
  ('db', (better_supabase.save_status_component('00000000-0000-4000-8000-000000000001', 'Internal DB', is_public => false) ->> 'id')::uuid);
select lives_ok(
  $$select better_supabase.save_status_page('00000000-0000-4000-8000-000000000001', 'acme', 'Acme status', published => true)$$,
  'an owner publishes the status page'
);
insert into ids values
  ('outage', (better_supabase.open_incident('00000000-0000-4000-8000-000000000001', jsonb_build_object(
    'title', 'API errors', 'severity', 'sev2', 'public', true, 'message', 'Looking into it',
    'impacts', jsonb_build_array(
      jsonb_build_object('componentId', (select id from ids where name = 'api'), 'impact', 'partial_outage'),
      jsonb_build_object('componentId', (select id from ids where name = 'db'), 'impact', 'major_outage'))
  )) ->> 'id')::uuid),
  ('secret', (better_supabase.open_incident('00000000-0000-4000-8000-000000000001', jsonb_build_object(
    'title', 'Secret breach', 'severity', 'sev1', 'message', 'Rotate the keys'
  )) ->> 'id')::uuid);
select lives_ok(
  $$select better_supabase.post_incident_update((select id from ids where name = 'outage'), 'identified', 'Internal note about the root cause', false)$$,
  'an owner posts a private update on a public incident'
);
select is(
  (select status from better_supabase.incident_status_components where id = (select id from ids where name = 'api')),
  'partial_outage',
  'an impact sets the component status'
);
grant select on ids to anon;

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select lives_ok(
  $$select better_supabase.open_incident('00000000-0000-4000-8000-000000000002', '{"title":"Globex outage","public":true,"message":"Globex is down"}'::jsonb)$$,
  'the Globex owner opens a public Globex incident'
);
select lives_ok(
  $$select better_supabase.save_status_page('00000000-0000-4000-8000-000000000002', 'globex', 'Globex status')$$,
  'the Globex owner saves an unpublished page'
);
select throws_ok(
  $$select better_supabase.save_status_page('00000000-0000-4000-8000-000000000002', 'acme', 'Taken')$$,
  '23505',
  null,
  'another organization cannot take a slug'
);
select is(
  (select count(*) from better_supabase.incidents where tenant_id = '00000000-0000-4000-8000-000000000001'),
  0::bigint,
  'the Globex owner reads no Acme incidents'
);
select throws_ok(
  $$select better_supabase.open_incident('00000000-0000-4000-8000-000000000001', '{"title":"Hijack"}'::jsonb)$$,
  '42501',
  null,
  'the Globex owner cannot open an Acme incident'
);

reset role;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
set local role anon;

select throws_ok(
  $$select count(*) from better_supabase.incidents$$,
  '42501',
  null,
  'anon cannot select incidents'
);
select throws_ok(
  $$select better_supabase.get_incident((select id from ids where name = 'secret'))$$,
  '42501',
  null,
  'anon cannot call get_incident'
);
select is(
  (select jsonb_path_query_array(better_supabase.public_status_page('acme'), '$.incidents[*].title')),
  '["API errors"]'::jsonb,
  'the page lists the public incident only'
);
select is(
  (select jsonb_path_query_array(better_supabase.public_status_page('acme'), '$.components[*].name')),
  '["API"]'::jsonb,
  'the page lists public components only'
);
select is(
  (select jsonb_path_query_array(better_supabase.public_status_page('acme'), '$.incidents[*].components[*].name')),
  '["API"]'::jsonb,
  'a public incident names only its public components'
);
select is(
  (select jsonb_path_query_array(better_supabase.public_status_page('acme'), '$.incidents[*].updates[*].body')),
  '["Looking into it"]'::jsonb,
  'the page shows public updates only'
);
select ok(
  (select better_supabase.public_status_page('acme')::text !~ '(Secret breach|Rotate the keys|Internal|Globex|organizationId|commander|00000000-0000-4000-8000-000000000001)'),
  'the page carries no private incident, other tenant, tenant id or member'
);
select is(
  better_supabase.public_status_page('globex'),
  null,
  'an unpublished page reads as null'
);
select is(
  (select better_supabase.public_status_page('acme', 7) -> 'components' -> 0 -> 'uptime' -> -1 ->> 'status'),
  'partial_outage',
  'today''s uptime cell shows the worst public status'
);

select * from finish();
rollback;
