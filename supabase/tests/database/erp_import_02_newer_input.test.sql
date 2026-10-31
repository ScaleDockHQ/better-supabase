-- ERP import acceptance 2 (ADR 0141): newer input updates only the records that
-- changed in the source and reports a record a user edited after the import as a
-- conflict, leaving the user's edit. Payment terms and tax codes update in
-- place; an imported invoice is kept as imported and the changed source reports
-- IMPORT_DOCUMENT_CHANGED. Run with `supabase test db`.
begin;
select plan(12);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

create function pg_temp.start_run(source text) returns void language plpgsql as $$
begin
  perform set_config('bsb.run', (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', source, '{}'::jsonb) ->> 'id'), true);
end;
$$;

select pg_temp.start_run('erp-newer');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

-- Run one: three terms, two tax codes, one invoice.
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
    '[{"key":"N14","data":{"code":"N14","name":"Net 14","days":14}},
      {"key":"N30","data":{"code":"N30","name":"Net 30","days":30}},
      {"key":"N60","data":{"code":"N60","name":"Net 60","days":60}}]'::jsonb) ->> 'inserted'),
  '3',
  'run one inserts three payment terms'
);
select is(
  (select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'tax_code',
    '[{"key":"VAT21","data":{"code":"VAT21","name":"VAT 21%","type":"sales","rateBps":2100,"returnBoxes":["1a"]}},
      {"key":"VAT9","data":{"code":"VAT9","name":"VAT 9%","type":"sales","rateBps":900,"returnBoxes":["1b"]}}]'::jsonb) ->> 'inserted'),
  '2',
  'run one inserts two tax codes'
);
select better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
  '[{"key":"inv-2001","data":{"number":"INV-2001","status":"issued","issuedOn":"2026-01-10","dueOn":"2026-02-09","currency":"EUR","title":"January",
    "lines":[{"description":"Service","quantity":1,"unitAmount":10000,"taxRateBps":2100}]}}]'::jsonb);
select better_supabase.finish_import_run(current_setting('bsb.run')::uuid);

-- A user edits N60 after the import.
update better_supabase.payment_terms set name = 'Sixty days (edited)', updated_at = now() + interval '1 hour'
where code = 'N60' and tenant_id = '00000000-0000-4000-8000-000000000001';

-- Run two: N14 changed, N30 the same, N60 changed in the source too, N45 is new.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;
select pg_temp.start_run('erp-newer');
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;
select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);

create temporary table out (name text primary key, result jsonb) on commit drop;
grant all on out to service_role, authenticated;

insert into out values ('terms', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'payment_term',
  '[{"key":"N14","data":{"code":"N14","name":"Net 14","days":21}},
    {"key":"N30","data":{"code":"N30","name":"Net 30","days":30}},
    {"key":"N45","data":{"code":"N45","name":"Net 45","days":45}},
    {"key":"N60","data":{"code":"N60","name":"Net 60","days":75}}]'::jsonb));

select is(
  (select result - 'errors' - 'dryRun' - 'warnings' from out where name = 'terms'),
  '{"inserted":1,"updated":1,"unchanged":1,"conflicted":1}'::jsonb,
  'newer input inserts the new term, updates the changed one, leaves the same one and conflicts the edited one'
);
select is(
  (select days from better_supabase.payment_terms where code = 'N14' and tenant_id = '00000000-0000-4000-8000-000000000001'),
  21,
  'the changed record carries the new value'
);
select is(
  (select days from better_supabase.payment_terms where code = 'N30' and tenant_id = '00000000-0000-4000-8000-000000000001'),
  30,
  'the unchanged record keeps its value'
);
select is(
  (select jsonb_build_array(name, days) from better_supabase.payment_terms where code = 'N60' and tenant_id = '00000000-0000-4000-8000-000000000001'),
  '["Sixty days (edited)", 60]'::jsonb,
  'the conflicting record keeps the user''s edit and is not overwritten'
);
-- Tax codes: only the changed one updates.
insert into out values ('codes', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'tax_code',
  '[{"key":"VAT21","data":{"code":"VAT21","name":"VAT 21%","type":"sales","rateBps":2100,"returnBoxes":["1a"]}},
    {"key":"VAT9","data":{"code":"VAT9","name":"VAT low rate","type":"sales","rateBps":900,"returnBoxes":["1b"]}}]'::jsonb));
select is(
  (select result - 'errors' - 'dryRun' - 'warnings' from out where name = 'codes'),
  '{"inserted":0,"updated":1,"unchanged":1,"conflicted":0}'::jsonb,
  'tax codes: one update, one unchanged'
);
select is(
  (select name from better_supabase.tax_codes where code = 'VAT9' and tenant_id = '00000000-0000-4000-8000-000000000001'),
  'VAT low rate',
  'the changed tax code carries its new name'
);

-- An imported invoice is kept as imported; a changed source is a warning.
insert into out values ('invoice', better_supabase.import_upsert_batch(current_setting('bsb.run')::uuid, 'invoice',
  '[{"key":"inv-2001","data":{"number":"INV-2001","status":"issued","issuedOn":"2026-01-10","dueOn":"2026-02-09","currency":"EUR","title":"January (corrected)",
    "lines":[{"description":"Service","quantity":2,"unitAmount":10000,"taxRateBps":2100}]}}]'::jsonb));
select is(
  (select result -> 'warnings' -> 0 ->> 'code' from out where name = 'invoice'),
  'IMPORT_DOCUMENT_CHANGED',
  'a changed source document reports IMPORT_DOCUMENT_CHANGED'
);
select is(
  (select total::text from better_supabase.invoices where identifier = 'INV-2001'),
  '12100',
  'the imported invoice keeps its imported total'
);
select is(
  (select count(*)::int from better_supabase.invoices where identifier = 'INV-2001'),
  1,
  'no second invoice appears'
);

select better_supabase.finish_import_run(current_setting('bsb.run')::uuid);

select is(
  (select better_supabase.get_import_run(current_setting('bsb.run')::uuid) -> 'counts' -> 'payment_term' ->> 'conflicted'),
  '1',
  'the run reports the edited record as a conflict in its counts'
);

select * from finish();
rollback;
