-- Attachment document types (ADR 0157): per-organization types with typed
-- metadata fields checked on write, a subject type that must be registered, a
-- source and external id that are unique per organization, and records an
-- import registers before the file exists (claim or mark missing later).
-- Acme (…0001) has the admin …a1 and the member …a2; Globex (…0002) has …a3.
begin;
select plan(34);

select has_table('better_supabase', 'attachment_document_types', 'document types have a table');
select has_column('better_supabase', 'attachments', 'external_id', 'attachments carry an external id');
select has_column('better_supabase', 'attachments', 'storage_status', 'attachments carry a storage status');
select has_function('better_supabase', 'claim_attachment_upload', array['uuid'], 'claim_attachment_upload exists');
select has_function('better_supabase', 'import_attachment', array['uuid', 'jsonb', 'text'], 'the attachment import target exists');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.define_attachment_document_type(
    '00000000-0000-4000-8000-000000000001', 'invoice', 'Invoice',
    '{"amount":{"type":"amount","required":true},"issued":{"type":"date"},"expires":{"type":"expiry"},"kind":{"type":"select","options":["sales","purchase"]}}'::jsonb
  ) ->> 'key',
  'invoice',
  'the admin defines a document type with typed fields'
);
select is(
  better_supabase.define_attachment_document_type(
    '00000000-0000-4000-8000-000000000001', 'invoice', 'Invoices',
    '{"amount":{"type":"amount","required":true},"issued":{"type":"date"},"expires":{"type":"expiry"},"kind":{"type":"select","options":["sales","purchase"]}}'::jsonb
  ) ->> 'name',
  'Invoices',
  'defining a key again changes the type'
);
select throws_ok(
  $$select better_supabase.define_attachment_document_type('00000000-0000-4000-8000-000000000001', 'bad', 'Bad', '{"x":{"type":"bogus"}}')$$,
  '22023',
  null,
  'a field type the schema doesn''t know is refused'
);
select throws_ok(
  $$select better_supabase.define_attachment_document_type('00000000-0000-4000-8000-000000000001', 'bad', 'Bad', '{"x":{"type":"select"}}')$$,
  '22023',
  null,
  'a select field needs options'
);

-- Metadata is validated against the type on write.
select lives_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'inv-1.pdf', mime_type => 'application/pdf', size => 10,
    subject_type => 'customer', subject_id => '00000000-0000-4000-8000-00000000a001',
    metadata => '{"amount":{"amount":1250,"currency":"EUR"},"issued":"2026-10-01","kind":"sales"}',
    document_type => 'invoice')$$,
  'a file with valid metadata for its type is created'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'inv-2.pdf', mime_type => 'application/pdf', size => 10,
    metadata => '{"issued":"2026-10-01"}', document_type => 'invoice')$$,
  '22023',
  null,
  'a required field must be present'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'inv-3.pdf', mime_type => 'application/pdf', size => 10,
    metadata => '{"amount":{"amount":"12.5","currency":"EUR"}}', document_type => 'invoice')$$,
  '22023',
  null,
  'an amount is a whole number of minor units'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'inv-4.pdf', mime_type => 'application/pdf', size => 10,
    metadata => '{"amount":{"amount":1,"currency":"EUR"},"issued":"2026-02-30"}', document_type => 'invoice')$$,
  '22023',
  null,
  'a date must exist'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'inv-5.pdf', mime_type => 'application/pdf', size => 10,
    metadata => '{"amount":{"amount":1,"currency":"EUR"},"kind":"other"}', document_type => 'invoice')$$,
  '22023',
  null,
  'a select value must be one of its options'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'x.pdf', mime_type => 'application/pdf', size => 10,
    document_type => 'missing')$$,
  '22023',
  null,
  'an unknown document type is refused'
);
select is(
  (select storage_status from better_supabase.attachments where name = 'inv-1.pdf'),
  'pending_upload',
  'a new record waits for its upload'
);

-- The subject type must be registered.
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'x.pdf', mime_type => 'application/pdf', size => 10,
    subject_type => 'not_a_subject', subject_id => '1')$$,
  '22023',
  null,
  'a subject type outside the registry is refused'
);

-- A source is an import source or one of options.sources.
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'x.pdf', mime_type => 'application/pdf', size => 10,
    source => 'erp', external_id => 'f-1')$$,
  '22023',
  null,
  'a source without an import run is refused'
);
select set_config(
  'bsb.run',
  (better_supabase.start_import_run('00000000-0000-4000-8000-000000000001', 'erp', '{}'::jsonb) ->> 'id'),
  true
);
select lives_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'a.pdf', mime_type => 'application/pdf', size => 10,
    source => 'erp', external_id => 'f-1')$$,
  'a source with an import run is accepted'
);
select throws_ok(
  $$select better_supabase.create_attachment(
    tenant => '00000000-0000-4000-8000-000000000001', name => 'b.pdf', mime_type => 'application/pdf', size => 10,
    source => 'erp', external_id => 'f-1')$$,
  '23505',
  null,
  'an external id is unique per organization and source'
);

-- Another organization has its own types and external ids.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a3","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  (select count(*)::int from better_supabase.attachment_document_types),
  0,
  'Globex sees none of Acme''s document types'
);
select throws_ok(
  $$select better_supabase.define_attachment_document_type('00000000-0000-4000-8000-000000000001', 'x', 'X')$$,
  '42501',
  null,
  'Globex can''t define a type in Acme'
);

-- The member reads types but doesn't manage them.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  jsonb_array_length(better_supabase.list_attachment_document_types('00000000-0000-4000-8000-000000000001')),
  1,
  'a member lists the organization''s types'
);
select throws_ok(
  $$select better_supabase.define_attachment_document_type('00000000-0000-4000-8000-000000000001', 'x', 'X')$$,
  '42501',
  null,
  'a member can''t define a type'
);

-- Import target: register the record now, settle it later.
reset role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
set local role service_role;

select better_supabase.mark_import_running(current_setting('bsb.run')::uuid);
select better_supabase.import_upsert_batch(
  current_setting('bsb.run')::uuid, 'customer', '[{"key":"c1","data":{"name":"Alpha","kvk":"1"}}]'::jsonb
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'attachment',
    '[{"key":"f-2","data":{"name":"inv-erp.pdf","mimeType":"application/pdf","size":2048,"subject":{"entity":"customer","key":"c1"},"sourcePath":"/inv/2.pdf","documentType":"invoice","metadata":{"amount":{"amount":990,"currency":"EUR"}}}}]'::jsonb
  ) - 'errors' - 'dryRun'),
  '{"inserted":1,"updated":0,"unchanged":0,"conflicted":0}'::jsonb,
  'the import registers the record before its file exists'
);
select is(
  (select storage_status || ':' || subject_type || ':' || source_path from better_supabase.attachments where source = 'erp' and external_id = 'f-2'),
  'pending_upload:customer:/inv/2.pdf',
  'the record is pending upload on the resolved customer'
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'attachment', '[{"key":"f-3","data":{"name":"x.pdf"}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  null,
  'a record without a subject or document type is accepted'
);
select is(
  (select better_supabase.import_upsert_batch(
    current_setting('bsb.run')::uuid, 'attachment', '[{"key":"f-4","data":{"name":"x.pdf","status":"stored"}}]'::jsonb
  ) -> 'errors' -> 0 ->> 'code'),
  'IMPORT_ITEM_INVALID',
  'an import can''t register a stored file'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.mark_attachment_missing(
    (select id from better_supabase.attachments where external_id = 'f-2')
  ) ->> 'storage_status',
  'missing',
  'a record whose file the source lacks is marked missing'
);
select is(
  better_supabase.claim_attachment_upload(
    (select id from better_supabase.attachments where external_id = 'f-2')
  ) ->> 'uploaded_by',
  '00000000-0000-4000-8000-0000000000a1',
  'claiming makes the caller the uploader and the record pending again'
);

reset role;
set local role postgres;
update better_supabase.attachments set uploaded_at = now() where external_id = 'f-2';
select is(
  (select storage_status from better_supabase.attachments where external_id = 'f-2'),
  'stored',
  'an uploaded file is stored'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
select throws_ok(
  format($$select better_supabase.claim_attachment_upload(%L::uuid)$$, (select id from better_supabase.attachments where external_id = 'f-2')),
  '55000',
  null,
  'a stored file can''t be claimed'
);
select throws_ok(
  format($$select better_supabase.mark_attachment_missing(%L::uuid)$$, (select id from better_supabase.attachments where external_id = 'f-2')),
  '55000',
  null,
  'a stored file can''t be marked missing'
);
select throws_ok(
  $$select better_supabase.delete_attachment_document_type('00000000-0000-4000-8000-000000000001', 'invoice')$$,
  '23503',
  null,
  'a type that files use can''t be deleted'
);

select * from finish();
rollback;
