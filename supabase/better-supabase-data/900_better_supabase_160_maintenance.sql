-- better-supabase module: maintenance
-- @bsb-block-data maintenance
-- @bsb-hash sha256:c5405f8bd581e3e574078225c7293446001e4c299880bcee098bca157453e5bf
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.maintenance_plans', target_type => 'maintenance_plan', event_prefix => 'maintenance_plan', deferred => true);
select better_supabase.audit('better_supabase.maintenance_plan_parts', target_type => 'maintenance_plan_part', event_prefix => 'maintenance_plan_part', deferred => true);
select better_supabase.audit('better_supabase.maintenance_meters', target_type => 'maintenance_meter', event_prefix => 'maintenance_meter', deferred => true);
select better_supabase.audit('better_supabase.maintenance_meter_readings', target_type => 'maintenance_meter_reading', event_prefix => 'maintenance_meter_reading', deferred => true);
select better_supabase.audit('better_supabase.maintenance_calibrations', target_type => 'maintenance_calibration', event_prefix => 'maintenance_calibration', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('maintenance', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
