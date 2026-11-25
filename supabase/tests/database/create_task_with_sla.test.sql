-- create_work_item_with_sla (ADR 1235): support.openTicket as one function.
-- The admin (…a1) of Acme (…0001) creates a work item and starts its SLA
-- clocks in one call. A failing clock start leaves no work item behind.
begin;
select plan(3);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.result', better_supabase.create_work_item_with_sla(
  '00000000-0000-4000-8000-000000000001',
  '{"title":"Payment API down"}',
  null,
  'work_item')::text, true);

select is(
  current_setting('test.result')::jsonb -> 'task' ->> 'title',
  'Payment API down',
  'the work item is created'
);
select is(
  jsonb_typeof(current_setting('test.result')::jsonb -> 'clocks'),
  'array',
  'the clocks come back as a list'
);
select is(
  (select count(*) from better_supabase.work_items where title = 'Payment API down'),
  1::bigint,
  'exactly one work item exists'
);

select * from finish();
rollback;
