-- Enrichment: provider results stored per company or person, filling only
-- empty columns. Acme (…0001) has the owner …a1 and the member …a2; Globex
-- (…0002) has the owner …a3 (supabase/seed.sql).
begin;
select plan(18);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, anon, service_role;

insert into ids values
  ('acme_co', gen_random_uuid()),
  ('taken_co', gen_random_uuid()),
  ('acme_person', gen_random_uuid()),
  ('globex_co', gen_random_uuid());
insert into better_supabase.companies (id, tenant_id, name, website, lifecycle) values
  ((select id from ids where name = 'acme_co'), '00000000-0000-4000-8000-000000000001', 'Initech', 'https://initech.example', 'lead'),
  ((select id from ids where name = 'globex_co'), '00000000-0000-4000-8000-000000000002', 'Hooli', 'https://hooli.example', 'lead');
insert into better_supabase.companies (id, tenant_id, name, domain, lifecycle) values
  ((select id from ids where name = 'taken_co'), '00000000-0000-4000-8000-000000000001', 'Initrode', 'initrode.example', 'lead');
insert into better_supabase.people (id, tenant_id, name, email, title, lifecycle) values
  ((select id from ids where name = 'acme_person'), '00000000-0000-4000-8000-000000000001', 'Peter', 'peter@initech.example', 'Engineer', 'lead');

-- Acme member: reads results, can't run a lookup.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select throws_ok(
  format($$select api.enrichment_target('company', %L)$$, (select id from ids where name = 'acme_co')),
  'P0002',
  null,
  'a member without enrichment.run cannot read the lookup target'
);
select throws_ok(
  format($$select api.record_enrichment('company', %L, 'pdl', '{"status":"not_found"}')$$, (select id from ids where name = 'acme_co')),
  'P0002',
  null,
  'a member without enrichment.run cannot record a result'
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
  api.enrichment_target('company', (select id from ids where name = 'acme_co')) ->> 'website',
  'https://initech.example',
  'the owner reads the company lookup target'
);
select is(
  api.enrichment_target('person', (select id from ids where name = 'acme_person')) ->> 'email',
  'peter@initech.example',
  'the owner reads the person lookup target'
);
select throws_ok(
  format($$select api.enrichment_target('company', %L)$$, (select id from ids where name = 'globex_co')),
  'P0002',
  null,
  'a company in another organization is not found'
);
select throws_ok(
  format($$select api.enrichment_target('deal', %L)$$, (select id from ids where name = 'acme_co')),
  '22023',
  null,
  'an unknown subject type is refused'
);
select throws_ok(
  format($$select api.record_enrichment('company', %L, 'pdl', '{"status":"maybe"}')$$, (select id from ids where name = 'acme_co')),
  '22023',
  null,
  'an unknown status is refused'
);
select throws_ok(
  format($$select api.record_enrichment('company', %L, 'PDL!', '{"status":"not_found"}')$$, (select id from ids where name = 'acme_co')),
  '22023',
  null,
  'a provider name that is not lowercase is refused'
);

select is(
  api.record_enrichment('company', (select id from ids where name = 'acme_co'), 'pdl',
    '{"status":"matched","data":{"domain":"Initrode.example","website":"https://other.example","industry":"software"}}') -> 'filled',
  '[]'::jsonb,
  'a domain another company holds and a set website are not filled'
);
select is(
  (select domain from better_supabase.companies where id = (select id from ids where name = 'acme_co')),
  null,
  'the domain stays empty'
);
select is(
  api.record_enrichment('company', (select id from ids where name = 'acme_co'), 'pdl',
    '{"status":"matched","data":{"domain":"Initech.example"}}') -> 'filled',
  '["domain"]'::jsonb,
  'a free domain fills the empty column'
);
select is(
  (select domain from better_supabase.companies where id = (select id from ids where name = 'acme_co')),
  'initech.example',
  'the domain is stored lowercased'
);
select is(
  (api.record_enrichment('person', (select id from ids where name = 'acme_person'), 'pdl',
    '{"status":"matched","data":{"title":"CTO","phone":"+31 20 123 4567"}}', true) -> 'filled'),
  '["phone"]'::jsonb,
  'the person gets the empty phone, and the set title is kept'
);
select is(
  api.record_enrichment('person', (select id from ids where name = 'acme_person'), 'other',
    '{"status":"not_found","data":{"title":"CEO"}}') ->> 'status',
  'not_found',
  'a not_found result is stored without data'
);
select is(
  (select count(*)::int from better_supabase.enrichments where company_id = (select id from ids where name = 'acme_co')),
  1,
  'a second result from the same provider replaces the first'
);

reset role;
select is(
  (select count(*)::int from better_supabase.outbox_events where type in ('company.enriched', 'person.enriched')),
  4,
  'every recorded result emits company.enriched or person.enriched'
);

-- The member reads the results, newest first.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(api.enrichments_of('person', (select id from ids where name = 'acme_person'))),
  2,
  'a member reads both results for the person'
);

-- The worker lists what is due.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select ok(
  not exists (
    select 1 from jsonb_array_elements(api.enrichment_due('pdl', 500)) d
    where (d ->> 'subjectId')::uuid in (select id from ids where name in ('acme_co', 'acme_person'))
  )
  and exists (
    select 1 from jsonb_array_elements(api.enrichment_due('pdl', 500)) d
    where (d ->> 'subjectId')::uuid = (select id from ids where name = 'taken_co')
  ),
  'fresh results are not due, and a never enriched company is'
);

select * from finish();
rollback;
