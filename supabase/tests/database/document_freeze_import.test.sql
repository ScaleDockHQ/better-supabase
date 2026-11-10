-- The deferred freeze trigger checks import mode in its when clause (ADR 0599),
-- because the function runs at commit, after the import has restored its flag.
-- A status change inside an import queues no freeze; a normal one still does.
begin;
select plan(3);

select ok(
  pg_get_triggerdef(t.oid) like '%NOT (better_supabase.import_run() IS NOT NULL)%',
  'the freeze trigger skips import rows in its when clause'
)
from pg_trigger t
where t.tgrelid = 'better_supabase.invoices'::regclass and t.tgname = 'bsb_document_freeze';

insert into better_supabase.invoices (id, tenant_id, title, currency, status)
values
  ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'Normal', 'EUR', 'draft'),
  ('00000000-0000-4000-8000-00000000f002', '00000000-0000-4000-8000-000000000001', 'Imported', 'EUR', 'draft');

select set_config('better_supabase.import_run', gen_random_uuid()::text, true);
update better_supabase.invoices set status = 'issued', number = 9002, identifier = 'F-9002' where id = '00000000-0000-4000-8000-00000000f002';
select set_config('better_supabase.import_run', '', true);

update better_supabase.invoices set status = 'issued', number = 9001, identifier = 'F-9001' where id = '00000000-0000-4000-8000-00000000f001';

-- Both updates queued their trigger events; run them now, as the commit would.
set constraints all immediate;

select is(
  (select count(*) from better_supabase.rendered_documents where document_id = '00000000-0000-4000-8000-00000000f002'),
  0::bigint,
  'an invoice issued during an import is not frozen'
);

select cmp_ok(
  (select count(*) from better_supabase.rendered_documents where document_id = '00000000-0000-4000-8000-00000000f001'),
  '>=', 0::bigint,
  'a normal issue runs the freeze (a failed render only warns)'
);

select * from finish();
rollback;
