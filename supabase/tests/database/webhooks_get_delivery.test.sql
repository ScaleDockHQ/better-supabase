-- better_supabase.get_webhook_delivery: one delivery for a caller who may read
-- its endpoint's tenant, the job source of dispatch and redeliver (ADR 1032).
-- The owner is …00a1 in Acme (…0001); supabase/seed.sql.
begin;
select plan(6);

create temp table fixture as
with endpoint as (
  insert into better_supabase.webhook_endpoints (tenant_id, name, url, event_types)
  values ('00000000-0000-4000-8000-000000000001', 'Test hook', 'https://example.com/hook', array['invoice.paid'])
  returning id
)
select e.id as endpoint,
  better_supabase.dispatch_webhook(e.id, 'invoice.paid', '{"id":1}'::jsonb) as delivery
from endpoint e;
grant select on fixture to authenticated;

select is(
  (select better_supabase.get_webhook_delivery('00000000-0000-4000-8000-0000000000ee')),
  null,
  'an unknown delivery reads as null'
);
select is(
  (select better_supabase.get_webhook_delivery(delivery) ->> 'status' from fixture),
  'pending',
  'the service reads a queued delivery as pending'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (select better_supabase.get_webhook_delivery(delivery) ->> 'type' from fixture),
  'invoice.paid',
  'a member who may read the tenant reads the delivery'
);
select is(
  (select better_supabase.get_webhook_delivery(delivery) ? 'responseStatus' from fixture),
  true,
  'the result carries the response status of the last attempt'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000fe","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select throws_ok(
  $$select better_supabase.get_webhook_delivery(delivery) from fixture$$,
  null,
  null,
  'a caller outside the tenant is refused'
);

reset role;
select is(
  (select count(*)::integer from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'better_supabase' and p.proname = 'get_webhook_delivery' and p.prosecdef),
  1,
  'get_webhook_delivery is one security definer function'
);

select * from finish();
rollback;
