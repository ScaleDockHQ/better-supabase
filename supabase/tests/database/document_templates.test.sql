-- The document-templates module against the seed (ADR 0145). The Acme owner
-- (…a1) saves templates for the organization and for one legal entity, the
-- fallback chain picks entity and language first, an unknown variable is
-- refused with a hint, a document takes the party's language, and an issued
-- invoice renders the same after its template is edited. The member (…a2)
-- reads but can't write, and the Globex owner (…a3) sees none of it. Run with
-- `supabase test db`.
begin;
select plan(30);

select is(
  (select count(*) from pg_catalog.pg_tables
   where schemaname = 'better_supabase'
     and tablename in ('document_templates', 'document_text_blocks', 'rendered_documents')
     and rowsecurity),
  3::bigint,
  'the document template tables have RLS enabled'
);
select table_privs_are('better_supabase', 'document_templates', 'anon', '{}'::text[],
  'anon has no privileges on templates');
select table_privs_are('better_supabase', 'document_templates', 'authenticated', array['SELECT'],
  'authenticated only reads templates; writes go through the functions');
select table_privs_are('better_supabase', 'rendered_documents', 'authenticated', array['SELECT'],
  'authenticated only reads frozen documents');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated;

select is(
  (better_supabase.document_template_contract('invoice') ->> 'version')::int,
  1,
  'the contract is version 1'
);
select ok(
  (select bool_or(v ->> 'path' = 'totals.subtotal')
   from jsonb_array_elements(better_supabase.document_template_contract('invoice') -> 'variables') v),
  'the invoice contract lists totals.subtotal'
);

insert into ids values ('nl', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'NL01', 'Acme B.V.') ->> 'id')::uuid);
insert into ids values ('de', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'DE01', 'Acme GmbH') ->> 'id')::uuid);

-- The chain: organization default, organization nl, entity DE01, entity DE01 de.
insert into ids values ('org', (better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
  'invoice', '<p>org {{document.number}}</p>') ->> 'id')::uuid);
insert into ids values ('org_nl', (better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
  'invoice', '<p>org nl {{document.number}}</p>', 'nl') ->> 'id')::uuid);
insert into ids values ('de_any', (better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
  'invoice', '<p>de any {{document.number}}</p>', null, 'default', (select id from ids where name = 'de')) ->> 'id')::uuid);
insert into ids values ('de_de', (better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
  'invoice', '<p>de de {{document.number}}</p>', 'DE', 'default', (select id from ids where name = 'de')) ->> 'id')::uuid);

select is(
  (select language from better_supabase.document_templates where id = (select id from ids where name = 'de_de')),
  'de',
  'a language is saved lowercase'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'de'), 'de') ->> 'id',
  (select id::text from ids where name = 'de_de'),
  'the entity and the language come first'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'de'), 'fr') ->> 'source',
  'entity',
  'the entity template for any language comes second'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'nl'), 'nl') ->> 'source',
  'organization_language',
  'an entity without a template falls back to the organization in the language'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'nl'), 'nl-NL') ->> 'id',
  (select id::text from ids where name = 'org_nl'),
  'a regional language matches its base language'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'nl'), 'fr') ->> 'source',
  'organization',
  'the organization default comes last'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    null, 'de') ->> 'id',
  (select id::text from ids where name = 'org'),
  'a null entity resolves to the default entity, which has no German template of its own'
);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'quote'),
  null::jsonb,
  'no template for a document type resolves to null'
);

select better_supabase.set_document_template_active((select id from ids where name = 'de_de'), false);
select is(
  better_supabase.resolve_document_template('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'de'), 'de') ->> 'id',
  (select id::text from ids where name = 'de_any'),
  'an inactive template leaves the chain'
);

-- Validation.
do $$
declare
  v_hint text;
begin
  begin
    perform better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
      'invoice', '<p>{{document.nope}}</p>', null, 'broken');
  exception when others then
    get stacked diagnostics v_hint = pg_exception_hint;
  end;
  perform set_config('test.hint', coalesce(v_hint, ''), true);
end $$;
select is(current_setting('test.hint'), 'DOCUMENT_TEMPLATE_UNKNOWN_VARIABLE',
  'an unknown variable is refused with its hint');
select throws_ok(
  $$select better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
    'invoice', '{{#each lines}}<p>{{description}}</p>', null, 'broken')$$,
  '22023', null, 'an unclosed block is refused'
);
select throws_ok(
  $$select better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
    'quote', '<p>{{shipping.carrier}}</p>', null, 'broken')$$,
  '22023', null, 'a variable of another document type is refused'
);
select is(
  (select count(*) from better_supabase.document_templates where name = 'broken'),
  0::bigint,
  'a refused template is not saved'
);

-- A document takes its party's language.
insert into ids values ('buyer', (better_supabase.save_company('00000000-0000-4000-8000-000000000001', null,
  '{"name": "<b>Buyer</b> B.V.", "language": "nl"}') ->> 'id')::uuid);
insert into ids values ('inv', (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Consulting', 'currency', 'EUR', 'company', jsonb_build_object('id', (select id from ids where name = 'buyer'))),
  jsonb_build_array(jsonb_build_object('description', 'Hours', 'quantity', 2, 'unitAmount', 5000))) ->> 'id')::uuid);

select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv')) ->> 'language',
  'nl',
  'the document language is the party language'
);
select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv')) -> 'template' ->> 'id',
  (select id::text from ids where name = 'org_nl'),
  'the template follows the party language'
);
select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv'), 'fr') -> 'template' ->> 'source',
  'organization',
  'a requested language overrides the party language'
);
select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv')) -> 'variables' -> 'buyer' ->> 'name',
  '<b>Buyer</b> B.V.',
  'variables stay raw; the renderer escapes them'
);

-- An issued invoice renders the same after its template is edited.
select better_supabase.issue_invoice((select id from ids where name = 'inv'), current_date);
set constraints all immediate;
select is(
  (better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv')) ->> 'frozen')::boolean,
  true,
  'issuing an invoice freezes its render'
);

select better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
  'invoice', '<p>edited {{document.number}}</p>', 'nl');
select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv')) -> 'template' ->> 'body',
  '<p>org nl {{document.number}}</p>',
  'a frozen document keeps its template body after an edit'
);
select is(
  better_supabase.render_document('00000000-0000-4000-8000-000000000001', 'invoice',
    (select id from ids where name = 'inv'), null, true) -> 'template' ->> 'body',
  '<p>edited {{document.number}}</p>',
  'fresh renders with the edited template'
);
select throws_ok(
  $$update better_supabase.rendered_documents set language = 'de'$$,
  '42501', null, 'authenticated cannot update a frozen document'
);

-- The member reads but cannot write.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select is(
  (select count(*) > 0 from better_supabase.document_templates),
  true,
  'a member reads the templates'
);
select throws_ok(
  $$select better_supabase.save_document_template('00000000-0000-4000-8000-000000000001',
    'invoice', '<p>x</p>', 'es')$$,
  '42501', null, 'a member cannot save a template'
);

-- Another organization sees none of it.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
select is(
  (select count(*) from better_supabase.document_templates),
  0::bigint,
  'another organization sees no templates'
);

select * from finish();
rollback;
