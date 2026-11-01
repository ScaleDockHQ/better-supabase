-- ERP known gaps 1 and 2 (ADR 0142): a document with no legal entity and a
-- document of the default entity are one number series, and turning legal
-- entities off needs a clean number space. The guard refuses a second
-- document with the same number, on a plain write and on a fixed import
-- number, and refuses to make an entity the default when that would merge two
-- documents with one number. legal_entities_disable_check lists the numbers
-- that more than one entity holds, in the clean and in the colliding case.
-- Run with `supabase test db`.
begin;
select plan(16);

create function pg_temp.hint_of(statement text) returns text
language plpgsql as $$
declare
  v_hint text;
begin
  execute statement;
  return null;
exception when others then
  get stacked diagnostics v_hint = pg_exception_hint;
  return v_hint;
end;
$$;
grant execute on function pg_temp.hint_of(text) to public;

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;

insert into ids values ('a', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'GAP-A', 'Gap A') ->> 'id')::uuid);
insert into ids values ('b', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'GAP-B', 'Gap B') ->> 'id')::uuid);

create temporary table drafts (name text primary key, id uuid) on commit drop;
grant all on drafts to authenticated, service_role;
insert into drafts
select n, (better_supabase.create_invoice('00000000-0000-4000-8000-000000000001',
  jsonb_build_object('title', 'Gap ' || n, 'currency', 'EUR', 'termsDays', 10),
  jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 1000))) ->> 'id')::uuid
from unnest(array['none', 'default', 'other', 'import']) n;

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

update better_supabase.invoices x set legal_entity_id = (select id from ids where name = 'a') where x.id = (select id from drafts where name = 'default');
update better_supabase.invoices x set legal_entity_id = (select id from ids where name = 'b') where x.id = (select id from drafts where name = 'other');

select is(
  (select is_default from better_supabase.legal_entities where id = (select id from ids where name = 'a')),
  true,
  'the first legal entity is the default'
);

select is(
  (select better_supabase.issue_invoice(id, '2026-05-01') ->> 'identifier' from drafts where name = 'none'),
  'INV-1',
  'a document without a legal entity takes the first number'
);
select is(
  (select better_supabase.issue_invoice(id, '2026-05-02') ->> 'identifier' from drafts where name = 'default'),
  'INV-2',
  'a document of the default entity continues the same series'
);
select is(
  (select better_supabase.issue_invoice(id, '2026-05-03') ->> 'identifier' from drafts where name = 'other'),
  'INV-1',
  'another entity counts its own series'
);

-- A number held by the null spelling can't be held by the default entity.
select is(
  pg_temp.hint_of(format($$update better_supabase.invoices set number = %s, identifier = 'INV-1' where id = %L$$,
    (select number from better_supabase.invoices where identifier = 'INV-1' and legal_entity_id is null),
    (select id from drafts where name = 'default'))),
  'LEGAL_ENTITY_NUMBER_TAKEN',
  'the default entity can not take a number a document without an entity holds'
);
select is(
  pg_temp.hint_of(format($$update better_supabase.invoices set legal_entity_id = null, number = %s, identifier = 'INV-2' where id = %L$$,
    (select number from better_supabase.invoices where identifier = 'INV-2'),
    (select id from drafts where name = 'none'))),
  'LEGAL_ENTITY_NUMBER_TAKEN',
  'a document without an entity can not take a number of the default entity'
);

-- A fixed number from an import follows the same rule.
select set_config('bsb.run', better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'gap-numbers', '{}'::jsonb) ->> 'id', true);
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);
select better_supabase.begin_import_session(current_setting('bsb.run')::uuid);

select is(
  pg_temp.hint_of(format($$select better_supabase.issue_invoice(%L, date '2026-05-04', null, null, 'INV-1')$$, (select id from drafts where name = 'import'))),
  'LEGAL_ENTITY_NUMBER_TAKEN',
  'a fixed import number can not repeat one the default series holds'
);
select set_config('better_supabase.import_run', '', true);

-- The default can't move to an entity whose numbers would merge with the
-- documents that have none.
select is(
  pg_temp.hint_of(format($$select better_supabase.set_default_legal_entity(%L)$$, (select id from ids where name = 'b'))),
  'LEGAL_ENTITY_DEFAULT_NUMBER_CONFLICT',
  'the default can not move where two documents would share a number'
);
select is(
  (select is_default from better_supabase.legal_entities where id = (select id from ids where name = 'a')),
  true,
  'the default stays where it was'
);

-- Another entity may repeat the number: the key is per entity.
select lives_ok(
  format($$update better_supabase.invoices set number = %s, identifier = 'INV-2' where id = %L$$,
    (select number from better_supabase.invoices where identifier = 'INV-2'),
    (select id from drafts where name = 'other')),
  'another entity can hold a number the default series holds'
);

-- Turning the option off: the colliding case lists what has to change.
select is(
  (select jsonb_build_array(c ->> 'kind', c ->> 'column', c ->> 'value', c -> 'documents')
   from jsonb_array_elements(better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001') -> 'collisions') c
   where c ->> 'column' = 'identifier'),
  '["invoices", "identifier", "INV-2", 2]'::jsonb,
  'the disable check lists the number two entities hold'
);
select is(
  better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001') ->> 'ok',
  'false',
  'the check is not ok while a number collides'
);
select is(
  better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001') -> 'defaultCollisions',
  '[]'::jsonb,
  'no number is held twice inside the default series'
);

-- The clean case: after the other entity renumbers, the check passes.
update better_supabase.invoices set number = 90, identifier = 'INV-90' where id = (select id from drafts where name = 'other');
select is(
  better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001') ->> 'ok',
  'true',
  'the check is ok once no entity repeats a number'
);
select is(
  better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001') -> 'collisions',
  '[]'::jsonb,
  'the clean case lists nothing'
);

-- The check needs the manage permission.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;
select throws_ok(
  $$select better_supabase.legal_entities_disable_check('00000000-0000-4000-8000-000000000001')$$,
  '42501', null, 'another organization can not run the check'
);

select * from finish();
rollback;
