-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:766ce6f17da496eb98f3fc55b02d29819491da1ed30e5f00d4fe21958f20c170
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.shipments', target_type => 'shipment', event_prefix => 'shipment', deferred => true);
select better_supabase.audit('better_supabase.shipment_packages', target_type => 'shipment_package', event_prefix => 'shipment_package', deferred => true);
select better_supabase.audit('better_supabase.shipment_tracking_events', target_type => 'shipment_tracking_event', event_prefix => 'shipment_tracking_event', deferred => true);
select better_supabase.audit('better_supabase.shipment_lines', target_type => 'shipment_line', event_prefix => 'shipment_line', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
