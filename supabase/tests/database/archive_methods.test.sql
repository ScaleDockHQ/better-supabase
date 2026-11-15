-- Archive and restore for invoices, risks, shipments and bookings (ADR 1028).
-- Each pair records its event once, an archive of an active shipment or
-- booking is refused, and the lists hide what is archived. Run with
-- `supabase test db`.
begin;
select plan(17);

create function pg_temp.n(t text) returns integer language sql security definer as $$
  select count(*)::integer from better_supabase.outbox_events where type = t
$$;

insert into better_supabase.invoices (id, tenant_id, title, currency, status)
values ('00000000-0000-4000-8000-00000000f001', '00000000-0000-4000-8000-000000000001', 'Archive me', 'EUR', 'draft');
insert into better_supabase.shipments (id, tenant_id, reference, status, from_address, to_address)
values
  ('00000000-0000-4000-8000-00000000f101', '00000000-0000-4000-8000-000000000001', 'SHP-CANCELLED', 'cancelled',
   '{"line1":"A 1","city":"Utrecht","country":"NL"}', '{"line1":"B 2","city":"Berlin","country":"DE"}'),
  ('00000000-0000-4000-8000-00000000f102', '00000000-0000-4000-8000-000000000001', 'SHP-DRAFT', 'draft',
   '{"line1":"A 1","city":"Utrecht","country":"NL"}', '{"line1":"B 2","city":"Berlin","country":"DE"}');
insert into better_supabase.booking_resources (id, tenant_id, name, capacity, tz)
values ('00000000-0000-4000-8000-00000000f201', '00000000-0000-4000-8000-000000000001', 'Room', 1, 'UTC');
insert into better_supabase.booking_services (id, tenant_id, name, duration)
values ('00000000-0000-4000-8000-00000000f211', '00000000-0000-4000-8000-000000000001', 'Visit', interval '1 hour');
insert into better_supabase.bookings (id, tenant_id, resource_id, service_id, seat, during, blocked, status, cancelled_at)
values
  ('00000000-0000-4000-8000-00000000f221', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f201',
   '00000000-0000-4000-8000-00000000f211', 1,
   tstzrange(now() + interval '1 day', now() + interval '1 day 1 hour'), tstzrange(now() + interval '1 day', now() + interval '1 day 1 hour'), 'cancelled', now()),
  ('00000000-0000-4000-8000-00000000f222', '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-00000000f201',
   '00000000-0000-4000-8000-00000000f211', 1,
   tstzrange(now() + interval '2 days', now() + interval '2 days 1 hour'), tstzrange(now() + interval '2 days', now() + interval '2 days 1 hour'), 'confirmed', null);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config(
  't.risk',
  better_supabase.create_risk('00000000-0000-4000-8000-000000000001', '{"title":"Archive risk","category":"quality"}') ->> 'id',
  true
);

-- invoices
select ok(better_supabase.archive_invoice('00000000-0000-4000-8000-00000000f001'), 'an invoice is archived');
select is(pg_temp.n('invoice.archived'), 1, 'archiving an invoice records invoice.archived');
select better_supabase.archive_invoice('00000000-0000-4000-8000-00000000f001');
select is(pg_temp.n('invoice.archived'), 1, 'a second archive records nothing');
select ok(better_supabase.restore_invoice('00000000-0000-4000-8000-00000000f001'), 'an invoice is restored');
select is(pg_temp.n('invoice.restored'), 1, 'restoring an invoice records invoice.restored');

-- risks
select is(
  better_supabase.archive_risk(current_setting('t.risk')::uuid) ->> 'archivedAt' is not null, true,
  'archiving a risk sets archivedAt'
);
select is(pg_temp.n('risk.archived'), 1, 'archiving a risk records risk.archived');
select is(
  better_supabase.restore_risk(current_setting('t.risk')::uuid) ->> 'archivedAt', null,
  'restoring a risk clears archivedAt'
);
select is(pg_temp.n('risk.restored'), 1, 'restoring a risk records risk.restored');

-- shipments
select throws_ok(
  $$select better_supabase.archive_shipment('00000000-0000-4000-8000-00000000f102')$$,
  '55000', null, 'a draft shipment is not archived'
);
select isnt(
  better_supabase.archive_shipment('00000000-0000-4000-8000-00000000f101') ->> 'archivedAt', null,
  'a cancelled shipment is archived'
);
select is(
  jsonb_array_length(better_supabase.list_shipments('00000000-0000-4000-8000-000000000001', '{"status":"cancelled"}')),
  0,
  'an archived shipment leaves the list'
);
select is(
  jsonb_array_length(better_supabase.list_shipments('00000000-0000-4000-8000-000000000001', '{"archived":"true"}')),
  1,
  'the archived filter lists it'
);
select is(
  better_supabase.restore_shipment('00000000-0000-4000-8000-00000000f101') ->> 'archivedAt', null,
  'a shipment is restored'
);

-- bookings
select throws_ok(
  $$select better_supabase.archive_booking('00000000-0000-4000-8000-00000000f222')$$,
  '55000', null, 'an upcoming booking is not archived'
);
select isnt(
  better_supabase.archive_booking('00000000-0000-4000-8000-00000000f221') ->> 'archivedAt', null,
  'a cancelled booking is archived'
);
select is(
  jsonb_array_length(better_supabase.list_bookings('00000000-0000-4000-8000-000000000001', now(), now() + interval '3 days')),
  1,
  'an archived booking leaves the list'
);

select * from finish();
rollback;
