-- The dispatch module on the fixture's access contract: the admin (…00a1) of
-- Acme (…0001) dispatches work orders at an asset location to the member
-- (…00a2), who works them as the technician. The member can't create or cancel
-- work orders, and Globex (…00b1) sees nothing.
begin;
select plan(22);

insert into auth.users (id, email, email_confirmed_at, aud, role, instance_id) values
  ('00000000-0000-4000-8000-0000000000e1', 'outsider@example.test', now(), 'authenticated', 'authenticated', '00000000-0000-0000-0000-000000000000');

select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select set_config('test.site', better_supabase.create_asset_location(
  '00000000-0000-4000-8000-000000000001', 'site', 'Plant'
) ->> 'id', true);
select set_config('test.asset', better_supabase.create_asset(
  '00000000-0000-4000-8000-000000000001', 'boiler', 'Boiler 1',
  location_id => current_setting('test.site')::uuid
) ->> 'id', true);

select set_config('test.backlog', better_supabase.create_work_order(
  '00000000-0000-4000-8000-000000000001', 'Service the boiler',
  priority => 'high',
  location_id => current_setting('test.site')::uuid,
  asset_id => current_setting('test.asset')::uuid
)::text, true);
select is(
  current_setting('test.backlog')::jsonb ->> 'status',
  'unscheduled',
  'a work order without a slot waits in the backlog'
);

select set_config('test.first', better_supabase.create_work_order(
  '00000000-0000-4000-8000-000000000001', 'Replace the valve',
  technician => '00000000-0000-4000-8000-0000000000a2',
  starts_at => '2030-01-07 09:00:00+00'
)::text, true);
select is(
  (current_setting('test.first')::jsonb ->> 'endsAt')::timestamptz,
  '2030-01-07 10:00:00+00'::timestamptz,
  'a slot without an end takes the default duration'
);
select is(
  current_setting('test.first')::jsonb ->> 'status',
  'scheduled',
  'a work order with a technician and a start is scheduled at once'
);

select throws_ok(
  $$select better_supabase.create_work_order('00000000-0000-4000-8000-000000000001', 'Overlap', technician => '00000000-0000-4000-8000-0000000000a2', starts_at => '2030-01-07 09:30:00+00')$$,
  '23P01',
  'the technician already has a work order in that slot',
  'a technician''s slots never overlap'
);
select throws_ok(
  $$select better_supabase.create_work_order('00000000-0000-4000-8000-000000000001', 'Outsider', technician => '00000000-0000-4000-8000-0000000000e1', starts_at => '2030-01-07 12:00:00+00')$$,
  '22023',
  'the technician is not a member who can do field work here',
  'only a member who can do field work is a technician'
);
select throws_ok(
  $$select better_supabase.create_work_order('00000000-0000-4000-8000-000000000001', 'Elsewhere', location_id => '00000000-0000-4000-8000-00000000ffff')$$,
  'P0002',
  'the location does not exist in this organization',
  'a work order''s location belongs to the organization'
);

select is(
  better_supabase.schedule_work_order(
    (current_setting('test.backlog')::jsonb ->> 'id')::uuid,
    '00000000-0000-4000-8000-0000000000a2',
    '2030-01-07 11:00:00+00', '2030-01-07 13:00:00+00'
  ) ->> 'status',
  'scheduled',
  'a dispatcher schedules a backlog work order into a free slot'
);

select better_supabase.create_work_order('00000000-0000-4000-8000-000000000001', 'Inspect the roof', priority => 'urgent');
select is(
  (
    select jsonb_build_array(
      jsonb_array_length(board -> 'scheduled'),
      board -> 'backlog' -> 0 ->> 'title',
      board -> 'technicianIds'
    )
    from better_supabase.dispatch_board('00000000-0000-4000-8000-000000000001', '2030-01-07', '2030-01-07') as board
  ),
  '[2, "Inspect the roof", ["00000000-0000-4000-8000-0000000000a2"]]'::jsonb,
  'the board shows the day''s slots, the technicians and the backlog'
);
select throws_ok(
  $$select better_supabase.dispatch_board('00000000-0000-4000-8000-000000000001', '2030-01-01', '2030-03-01')$$,
  '22023',
  'the board spans 1 to 31 days',
  'the board reads at most 31 days'
);

select better_supabase.plan_dispatch_route(
  '00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', '2030-01-07',
  array[(current_setting('test.backlog')::jsonb ->> 'id')::uuid, (current_setting('test.first')::jsonb ->> 'id')::uuid]
);
select throws_ok(
  $$select better_supabase.plan_dispatch_route('00000000-0000-4000-8000-000000000001', '00000000-0000-4000-8000-0000000000a2', '2030-01-07', array['00000000-0000-4000-8000-00000000ffff'::uuid])$$,
  '22023',
  'every stop must be a live work order of this technician',
  'a route only lists the technician''s own work orders'
);

-- The member works their day as the technician.
reset role;
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000a2","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000001"}}',
  true
);
set local role authenticated;

select is(
  (
    select jsonb_agg(stop -> 'workOrder' ->> 'title' order by (stop ->> 'position')::int)
    from jsonb_array_elements(better_supabase.technician_day('00000000-0000-4000-8000-000000000001', '2030-01-07') -> 'stops') stop
  ),
  '["Service the boiler", "Replace the valve"]'::jsonb,
  'the technician''s day follows the planned route'
);

select is(
  better_supabase.set_work_order_status((current_setting('test.first')::jsonb ->> 'id')::uuid, 'en_route') ->> 'status',
  'en_route',
  'the technician heads out'
);
select throws_ok(
  format(
    $$select better_supabase.set_work_order_status(%L, 'done')$$,
    current_setting('test.first')::jsonb ->> 'id'
  ),
  '55000',
  'a work order can''t move to that status from where it is',
  'a work order is done only after the technician is on site'
);
select better_supabase.set_work_order_status((current_setting('test.first')::jsonb ->> 'id')::uuid, 'on_site');
select is(
  better_supabase.set_work_order_status((current_setting('test.first')::jsonb ->> 'id')::uuid, 'done', 'Valve replaced') ->> 'completionNote',
  'Valve replaced',
  'the technician finishes with a note'
);

select is(
  better_supabase.record_work_order_part(
    (current_setting('test.backlog')::jsonb ->> 'id')::uuid, 'Gasket', 2,
    asset_id => current_setting('test.asset')::uuid
  ) ->> 'quantity',
  '2.000',
  'the technician records a part linked to the asset'
);
select is(
  jsonb_array_length(better_supabase.list_work_order_parts((current_setting('test.backlog')::jsonb ->> 'id')::uuid)),
  1,
  'the work order lists its parts'
);

select throws_ok(
  $$select better_supabase.create_work_order('00000000-0000-4000-8000-000000000001', 'Mine')$$,
  '42501',
  'not allowed to manage work orders',
  'a member without dispatch.manage cannot create work orders'
);
select throws_ok(
  format(
    $$select better_supabase.set_work_order_status(%L, 'cancelled')$$,
    current_setting('test.backlog')::jsonb ->> 'id'
  ),
  '42501',
  'only a dispatcher can cancel a work order',
  'only a dispatcher cancels'
);
select throws_ok(
  $$update better_supabase.work_orders set title = title$$,
  '42501',
  null,
  'the work orders table is written through the functions only'
);

reset role;
select is(
  (
    select array_agg(distinct type order by type)
    from better_supabase.outbox_events
    where type like 'work_order.%' or type = 'dispatch_route.planned'
  ),
  array['dispatch_route.planned', 'work_order.created', 'work_order.part_used', 'work_order.scheduled', 'work_order.status_changed'],
  'every change records an event'
);

-- Globex.
select set_config(
  'request.jwt.claims',
  '{"sub":"00000000-0000-4000-8000-0000000000b1","role":"authenticated","app_metadata":{"tenant_id":"00000000-0000-4000-8000-000000000002"}}',
  true
);
set local role authenticated;

select is(
  better_supabase.get_work_order((current_setting('test.first')::jsonb ->> 'id')::uuid),
  null,
  'another organization does not see the work order'
);
select is(
  (select count(*) from better_supabase.work_orders),
  0::bigint,
  'another organization reads none of the work orders directly'
);

select * from finish();
rollback;
