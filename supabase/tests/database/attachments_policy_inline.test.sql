-- The attachments read and insert policies inline the subject check instead of
-- calling attachment_subject_readable once per row (ADR 0424), and still hide
-- an attachment whose subject the caller cannot read.
begin;
select plan(4);

select is(
  (select count(*)::int from pg_policies
    where schemaname = 'better_supabase' and tablename = 'attachments'
      and (qual like '%attachment_subject_readable%' or with_check like '%attachment_subject_readable%')),
  0,
  'no attachments policy calls attachment_subject_readable per row'
);
select ok(
  (select bool_or(qual like '%''customer''%') from pg_policies where schemaname = 'better_supabase' and tablename = 'attachments' and cmd = 'SELECT'),
  'the read policy checks the subject types inline'
);

insert into public.customers (id, organization_id, name)
values ('00000000-0000-4000-8000-00000000d001', '00000000-0000-4000-8000-000000000001', 'Inline subject');
insert into better_supabase.attachments (id, tenant_id, bucket, subject_type, subject_id, name, mime_type, size, uploaded_by)
values ('00000000-0000-4000-8000-00000000d101', '00000000-0000-4000-8000-000000000001', 'attachments', 'customer', '00000000-0000-4000-8000-00000000d001', 'a.txt', 'text/plain', 1, '00000000-0000-4000-8000-0000000000a1');

select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}', true);
set local role authenticated;
select is((select count(*)::int from better_supabase.attachments where id = '00000000-0000-4000-8000-00000000d101'), 1, 'a member reads the attachment of a customer they read');

reset role;
select set_config('request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b9","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}', true);
set local role authenticated;
select is((select count(*)::int from better_supabase.attachments where id = '00000000-0000-4000-8000-00000000d101'), 0, 'another tenant reads nothing');

select * from finish();
rollback;
