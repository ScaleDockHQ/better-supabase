-- ERP import acceptance 3 (ADR 0141, 0142): two source administrations with a
-- cloned history import into one organization and two legal entities without
-- duplicates. Administration B was cloned from A, so both hold the same
-- invoices, credit note and payment terms; B also has invoices of its own.
-- `scopeAliases` makes B's scope reuse the subjects of A's records, so the
-- cloned history exists once and B's own documents land in the second legal
-- entity. Run with `supabase test db`.
begin;
select plan(11);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create temporary table ids (name text primary key, id uuid) on commit drop;
grant all on ids to authenticated, service_role;

insert into ids values ('a', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'ADM-A', 'Administration A B.V.') ->> 'id')::uuid);
insert into ids values ('b', (better_supabase.create_legal_entity('00000000-0000-4000-8000-000000000001', 'ADM-B', 'Administration B B.V.') ->> 'id')::uuid);

select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp-admins',
    '{"scopeAliases":[{"scope":"B","of":"A","entities":["payment_term","invoice","credit_note"]}]}'::jsonb) ->> 'id'),
  true
);

reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

-- The cloned history, as administration A holds it.
create function pg_temp.history(scope text, entity uuid) returns jsonb language sql as $$
  select jsonb_build_array(
    jsonb_build_object('key', 'inv-1', 'scope', scope, 'data', jsonb_build_object(
      'number', 'INV-0001', 'status', 'issued', 'issuedOn', '2025-01-10', 'dueOn', '2025-02-09', 'currency', 'EUR',
      'legalEntityId', entity, 'lines', jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 1, 'unitAmount', 10000, 'taxRateBps', 2100)))),
    jsonb_build_object('key', 'inv-2', 'scope', scope, 'data', jsonb_build_object(
      'number', 'INV-0002', 'status', 'issued', 'issuedOn', '2025-02-10', 'dueOn', '2025-03-12', 'currency', 'EUR',
      'legalEntityId', entity, 'lines', jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 2, 'unitAmount', 10000, 'taxRateBps', 2100)))),
    jsonb_build_object('key', 'inv-3', 'scope', scope, 'data', jsonb_build_object(
      'number', 'INV-0003', 'status', 'issued', 'issuedOn', '2025-03-10', 'dueOn', '2025-04-09', 'currency', 'EUR',
      'legalEntityId', entity, 'lines', jsonb_build_array(jsonb_build_object('description', 'Service', 'quantity', 3, 'unitAmount', 10000, 'taxRateBps', 2100)))));
$$;

select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
    '[{"key":"N30","scope":"A","data":{"code":"N30","name":"Net 30","days":30}}]'::jsonb) ->> 'inserted'),
  '1',
  'administration A brings its payment terms'
);
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
    '[{"key":"N30","scope":"B","data":{"code":"N30","name":"Net 30","days":30}}]'::jsonb) ->> 'unchanged'),
  '1',
  'the cloned payment terms of B are the same record'
);

select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
    pg_temp.history('A', (select id from ids where name = 'a'))) ->> 'inserted'),
  '3',
  'administration A inserts its three invoices'
);
select is(
  (select (better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
    pg_temp.history('B', (select id from ids where name = 'a'))) - 'errors' - 'dryRun' - 'warnings')),
  '{"inserted":0,"updated":0,"unchanged":3,"conflicted":0}'::jsonb,
  'the cloned history of B is unchanged, so nothing is written twice'
);
select is(
  (select count(*)::int from better_supabase.invoices where identifier in ('INV-0001', 'INV-0002', 'INV-0003')),
  3,
  'each cloned invoice exists once'
);

-- B's own documents carry B's legal entity and their own numbers.
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
    jsonb_build_array(jsonb_build_object('key', 'inv-b-1', 'scope', 'B', 'data', jsonb_build_object(
      'number', 'INV-B-0101', 'status', 'issued', 'issuedOn', '2025-04-01', 'dueOn', '2025-05-01', 'currency', 'EUR',
      'legalEntityId', (select id from ids where name = 'b'),
      'lines', jsonb_build_array(jsonb_build_object('description', 'Own work', 'quantity', 1, 'unitAmount', 5000, 'taxRateBps', 2100)))))) ->> 'inserted'),
  '1',
  'an invoice only B has is inserted'
);
select is(
  (select jsonb_build_object('a', count(*) filter (where legal_entity_id = (select id from ids where name = 'a')),
     'b', count(*) filter (where legal_entity_id = (select id from ids where name = 'b')))
   from better_supabase.invoices where identifier in ('INV-0001', 'INV-0002', 'INV-0003', 'INV-B-0101')),
  '{"a": 3, "b": 1}'::jsonb,
  'the cloned history belongs to the first legal entity and B''s own invoice to the second'
);
select is(
  (select count(*)::int from better_supabase.payment_terms where code = 'N30' and tenant_id = '00000000-0000-4000-8000-000000000001'),
  1,
  'the cloned payment term exists once'
);
select is(
  (select jsonb_agg(m.key order by m.key) from jsonb_to_recordset(better_supabase.import_resolve(current_setting('bsb.run')::uuid, 'invoice',
    '[{"key":"inv-2","scope":"B"},{"key":"inv-2","scope":"A"}]'::jsonb)) as m(key text, "subjectId" text)
   having count(distinct m."subjectId") = 1),
  '["inv-2", "inv-2"]'::jsonb,
  'both scopes resolve a cloned key to one subject'
);

-- Known gap: invoices are unique per (tenant, direction, kind, number), not per
-- legal entity, so two entities of one organization cannot both hold number 1
-- of their own series, although numbering counts per entity.
select todo_start('invoice numbers are unique per organization, not per legal entity');
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
    jsonb_build_array(jsonb_build_object('key', 'inv-b-same', 'scope', 'B', 'data', jsonb_build_object(
      'number', 'INV-0001', 'status', 'issued', 'issuedOn', '2025-04-02', 'dueOn', '2025-05-02', 'currency', 'EUR',
      'legalEntityId', (select id from ids where name = 'b'),
      'lines', jsonb_build_array(jsonb_build_object('description', 'Own work', 'quantity', 1, 'unitAmount', 5000, 'taxRateBps', 2100)))))) ->> 'inserted'),
  '1',
  'the second legal entity can hold the same number as the first'
);
select todo_end();

select better_supabase.finish_import_run(current_setting('bsb.run')::uuid);

select is(
  (select jsonb_build_array(
    better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'counts' -> 'invoice' ->> 'inserted',
    better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'counts' -> 'invoice' ->> 'unchanged')),
  '["4", "3"]'::jsonb,
  'the run reports four inserted invoices and three unchanged'
);

select * from finish();
rollback;
