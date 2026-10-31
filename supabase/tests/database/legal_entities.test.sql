-- The legal-entities module against the seed (ADR 0142). The Acme owner (…a1)
-- creates two legal entities, the first becomes the default, one default
-- holds per organization, and a setting resolves from the legal entity to the
-- organization to the code default. The member (…a2) reads but can't change
-- anything, and the Globex owner (…a3) sees none of it and gets null for the
-- default entity. Run with `supabase test db`.
begin;
select plan(33);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('legal_entities', 'legal_entity_settings')
     and rowsecurity),
  2::bigint,
  'the legal entity tables have RLS enabled'
);
select table_privs_are('better_supabase', 'legal_entities', 'anon', '{}'::text[],
  'anon has no privileges on legal entities');
select table_privs_are('better_supabase', 'legal_entities', 'authenticated', array['SELECT'],
  'authenticated only reads legal entities; writes go through the functions');
select table_privs_are('better_supabase', 'legal_entity_settings', 'anon', '{}'::text[],
  'anon has no privileges on legal entity settings');
select has_column('better_supabase', 'invoices', 'legal_entity_id', 'invoices carry the optional legal entity');
select has_column('better_supabase', 'number_sequences', 'legal_entity_id', 'number sequences carry the optional legal entity');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.legal_entity_of('00000000-0000-4000-8000-000000000001'),
  null::uuid,
  'an organization without legal entities resolves to null'
);

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

insert into ids values ('nl', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'NL01', 'Acme B.V.',
  '{"city": "Utrecht"}', 'NL123456789B01', null, 'NL91 ABNA 0417 1643 00', null, null, 'eur',
  '{"taxPeriod": "monthly"}') ->> 'id')::uuid);
select is(
  (select jsonb_build_array(x -> 'isDefault', x -> 'iban', x -> 'defaultCurrency', x -> 'fiscal')
   from (select better_supabase.get_legal_entity((select id from ids where name = 'nl')) as x) q),
  '[true, "NL91ABNA0417164300", "EUR", {"taxPeriod": "monthly", "fiscalYearStartMonth": 1}]'::jsonb,
  'the first legal entity is the default, with a clean IBAN, currency and fiscal calendar'
);

insert into ids values ('de', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'DE01', 'Acme GmbH') ->> 'id')::uuid);
select is(
  (select array_agg(code order by code) from better_supabase.legal_entities where is_default),
  array['NL01'],
  'a second legal entity is not the default'
);
select throws_ok(
  $$select better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'DE01', 'Again')$$,
  '23505', null, 'a code is unique per organization'
);
select throws_ok(
  $$select better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'X', 'Bad fiscal', null, null, null, null, null, null, null, '{"fiscalYearStartMonth": 13}')$$,
  '22023', null, 'the fiscal year starts in a month from 1 to 12'
);
select throws_ok(
  $$select better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'X', 'Bad fiscal', null, null, null, null, null, null, null, '{"taxPeriod": "yearly"}')$$,
  '22023', null, 'the tax period is monthly or quarterly'
);

select is(
  better_supabase.legal_entity_of('00000000-0000-4000-8000-000000000001'),
  (select id from ids where name = 'nl'),
  'a null legal entity resolves to the default'
);
select is(
  better_supabase.legal_entity_of('00000000-0000-4000-8000-000000000001', (select id from ids where name = 'de')),
  (select id from ids where name = 'de'),
  'a given legal entity resolves to itself'
);

select better_supabase.set_default_legal_entity((select id from ids where name = 'de'));
select is(
  (select array_agg(code order by code) from better_supabase.legal_entities where is_default),
  array['DE01'],
  'making another entity the default moves the flag'
);
select throws_ok(
  format($$select better_supabase.set_legal_entity_archived(%L)$$, (select id from ids where name = 'de')),
  '22023', null, 'the default entity can''t be archived'
);
select is(
  (better_supabase.set_legal_entity_archived((select id from ids where name = 'nl')) ->> 'archivedAt') is not null,
  true,
  'another entity can be archived'
);
select is(
  jsonb_array_length(better_supabase.list_legal_entities('00000000-0000-4000-8000-000000000001')),
  1,
  'the list hides archived entities'
);
select is(
  jsonb_array_length(better_supabase.list_legal_entities('00000000-0000-4000-8000-000000000001', true)),
  2,
  'the list shows archived entities on request'
);
select throws_ok(
  format($$select better_supabase.set_default_legal_entity(%L)$$, (select id from ids where name = 'nl')),
  '22023', null, 'an archived entity can''t become the default'
);
select better_supabase.set_legal_entity_archived((select id from ids where name = 'nl'), false);

-- The default entity is DE01 here, so a null legal entity reads its settings.
select is(
  better_supabase.resolve_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer') ->> 'source',
  'default',
  'a setting nobody set resolves to the code default'
);
select better_supabase.set_organization_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer', '{"value": "Thanks"}');
select is(
  better_supabase.resolve_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer', (select id from ids where name = 'nl')) ->> 'source',
  'organization',
  'an entity without its own value gets the organization''s'
);
select better_supabase.set_legal_entity_setting((select id from ids where name = 'nl'), 'invoice.footer', '{"value": "Bedankt"}');
select is(
  better_supabase.resolve_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer', (select id from ids where name = 'nl')),
  jsonb_build_object('value', 'Bedankt', 'source', 'legal_entity', 'legalEntityId', (select id from ids where name = 'nl')),
  'the legal entity''s own value wins'
);
select is(
  better_supabase.resolve_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer') ->> 'source',
  'organization',
  'without an entity the default entity answers, and it falls back to the organization'
);
select is(
  better_supabase.reset_legal_entity_setting((select id from ids where name = 'nl'), 'invoice.footer'),
  true,
  'resetting removes the entity''s value'
);
select is(
  better_supabase.resolve_setting('00000000-0000-4000-8000-000000000001', 'invoice.footer', (select id from ids where name = 'nl')) ->> 'value',
  'Thanks',
  'after a reset the organization''s value applies again'
);

reset role;
select throws_ok(
  $$insert into better_supabase.legal_entities (tenant_id, code, name, is_default)
    values ('00000000-0000-4000-8000-000000000001', 'DE02', 'Second default', true)$$,
  '23505', null, 'the database allows one default entity per organization'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_legal_entities('00000000-0000-4000-8000-000000000001')),
  2,
  'a member reads the legal entities'
);
select throws_ok(
  $$select better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'FR01', 'Acme SARL')$$,
  '42501', null, 'a member cannot create a legal entity'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*) from better_supabase.legal_entities) + (select count(*) from better_supabase.legal_entity_settings),
  0::bigint,
  'the Globex owner sees no Acme legal entities or settings'
);
select is(
  better_supabase.legal_entity_of('00000000-0000-4000-8000-000000000002'),
  null::uuid,
  'Globex has no legal entity yet'
);
select throws_ok(
  format($$select better_supabase.update_legal_entity(%L, '{"name": "Hijacked"}')$$, (select id from ids where name = 'de')),
  '42501', null, 'the Globex owner cannot change an Acme legal entity'
);
select throws_ok(
  format($$select better_supabase.legal_entity_of('00000000-0000-4000-8000-000000000002', %L)$$, (select id from ids where name = 'de')),
  'P0002', null, 'an entity of another organization does not resolve'
);
select * from finish();
rollback;
