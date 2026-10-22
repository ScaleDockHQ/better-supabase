-- The shipments module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) creates a shipment, stores the label a carrier sold and tracks
-- it to the door, and the service role ingests a carrier webhook. The member
-- (…00a2) reads shipments but can't create them, and Globex (…00b1) sees
-- nothing.
begin;
select plan(20);

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.ship', better_supabase.create_shipment(
  '00000000-0000-4000-8000-000000000001',
  '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}',
  '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}',
  '[{"weightGrams": 1000, "lengthMm": 300}, {"weightGrams": 500}]',
  reference => 'SHP-1'
)::text, true);
select is(
  jsonb_build_array(
    current_setting('test.ship')::jsonb ->> 'status',
    jsonb_array_length(current_setting('test.ship')::jsonb -> 'packages')
  ),
  '["draft", 2]'::jsonb,
  'a new shipment is a draft with its packages'
);

select throws_ok(
  $$select better_supabase.create_shipment('00000000-0000-4000-8000-000000000001', '{"line1": "Dock 4", "city": "Rotterdam", "country": "nl"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[{"weightGrams": 1}]')$$,
  '22023',
  'each address needs line1, city and a two-letter country',
  'an address needs a two-letter country'
);
select throws_ok(
  $$select better_supabase.create_shipment('00000000-0000-4000-8000-000000000001', '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[]')$$,
  '22023',
  'a shipment holds 1 to 50 packages',
  'a shipment holds at least one package'
);
select throws_ok(
  $$select better_supabase.create_shipment('00000000-0000-4000-8000-000000000001', '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[{"weightGrams": 0}]')$$,
  '22023',
  'each package needs a weightGrams and sizes in whole millimeters above zero',
  'a package weighs more than nothing'
);

select is(
  (
    select jsonb_build_array(label ->> 'status', label ->> 'labelCost', label ->> 'currency')
    from better_supabase.set_shipment_label(
      (current_setting('test.ship')::jsonb ->> 'id')::uuid, 'flat-rate', 'standard', 'FR1', 'lbl_1', 695, 'EUR',
      label_url => 'https://labels.example.test/lbl_1.pdf'
    ) as label
  ),
  '["label_created", "695", "EUR"]'::jsonb,
  'a stored label moves the shipment to label_created'
);
select throws_ok(
  format(
    $$select better_supabase.set_shipment_label(%L, 'flat-rate', 'standard', 'FR2', 'lbl_2', 695, 'EUR')$$,
    current_setting('test.ship')::jsonb ->> 'id'
  ),
  '55000',
  'only a draft shipment gets a label',
  'a shipment gets one label'
);

select is(
  better_supabase.record_tracking_events(
    (current_setting('test.ship')::jsonb ->> 'id')::uuid,
    '[{"id": "e1", "status": "in_transit", "occurredAt": "2030-01-07T10:00:00Z"}, {"id": "e0", "status": "out_for_delivery", "occurredAt": "2030-01-07T08:00:00Z"}]'
  ) -> 'shipment' ->> 'status',
  'in_transit',
  'the status follows the latest event, not the last one recorded'
);
select is(
  (better_supabase.record_tracking_events(
    (current_setting('test.ship')::jsonb ->> 'id')::uuid,
    '[{"id": "e1", "status": "in_transit", "occurredAt": "2030-01-07T10:00:00Z"}]'
  ) ->> 'recorded')::int,
  0,
  'an event id is recorded once'
);
select throws_ok(
  format(
    $$select better_supabase.record_tracking_events(%L, '[{"id": "e9", "status": "lost", "occurredAt": "2030-01-07T11:00:00Z"}]')$$,
    current_setting('test.ship')::jsonb ->> 'id'
  ),
  '22023',
  'each tracking event needs an id, a known status and an ISO 8601 occurredAt',
  'a tracking event has a known status'
);

select throws_ok(
  $$select better_supabase.ingest_tracking_events('flat-rate', 'FR1', '[]')$$,
  '42501',
  null,
  'only the service role ingests carrier webhooks'
);
reset role;
set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);

select is(
  better_supabase.ingest_tracking_events('flat-rate', 'NOPE', '[]'),
  null,
  'a webhook for an unknown tracking number changes nothing'
);
select is(
  (
    select jsonb_build_array(ingested ->> 'status', ingested ->> 'recorded')
    from better_supabase.ingest_tracking_events(
      'flat-rate', 'FR1',
      '[{"id": "e2", "status": "delivered", "occurredAt": "2030-01-07T15:00:00Z", "location": "Berlin"}]'
    ) as ingested
  ),
  '["delivered", "1"]'::jsonb,
  'a carrier webhook records its events and moves the status'
);
select is(
  (better_supabase.ingest_tracking_events(
    'flat-rate', 'FR1',
    '[{"id": "e2", "status": "delivered", "occurredAt": "2030-01-07T15:00:00Z"}]'
  ) ->> 'recorded')::int,
  0,
  'a redelivered webhook records nothing'
);

reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (
    select jsonb_agg(event ->> 'status')
    from jsonb_array_elements(better_supabase.list_tracking_events((current_setting('test.ship')::jsonb ->> 'id')::uuid)) event
  ),
  '["label_created", "out_for_delivery", "in_transit", "delivered"]'::jsonb,
  'the timeline lists the events in the order they happened'
);
select throws_ok(
  format(
    $$select better_supabase.cancel_shipment(%L)$$,
    current_setting('test.ship')::jsonb ->> 'id'
  ),
  '55000',
  'only a draft or a shipment that hasn''t left gets cancelled',
  'a delivered shipment cannot be cancelled'
);
select throws_ok(
  $$select count(*) from better_supabase.shipments$$,
  '42501',
  null,
  'the shipments table is read through the functions only'
);

reset role;
select is(
  (
    select array_agg(distinct type order by type)
    from better_supabase.outbox_events
    where type like 'shipment.%'
  ),
  array['shipment.created', 'shipment.labeled', 'shipment.status_changed'],
  'every change records an event'
);

-- Acme member with shipments.read only.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.get_shipment((current_setting('test.ship')::jsonb ->> 'id')::uuid) ->> 'trackingNumber',
  'FR1',
  'a member reads shipments'
);
select throws_ok(
  $$select better_supabase.create_shipment('00000000-0000-4000-8000-000000000001', '{"line1": "Dock 4", "city": "Rotterdam", "country": "NL"}', '{"line1": "Main St 1", "city": "Berlin", "country": "DE"}', '[{"weightGrams": 1}]')$$,
  '42501',
  'not allowed to manage shipments',
  'a member without shipments.manage cannot create shipments'
);

-- Globex.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.get_shipment((current_setting('test.ship')::jsonb ->> 'id')::uuid),
  null,
  'another organization does not see the shipment'
);

select * from finish();
rollback;
