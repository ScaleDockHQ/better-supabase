-- better-supabase module: manufacturing
-- @bsb-block-data manufacturing
-- @bsb-hash sha256:198cbaba581216c401cfe3cd3f8d8edf860ac28b2bafad8bf3bfcb84f4c2c491
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.production_orders', target_type => 'production_order', event_prefix => 'production_order', deferred => true);
select better_supabase.audit('better_supabase.boms', target_type => 'bom', event_prefix => 'bom', deferred => true);
select better_supabase.audit('better_supabase.bom_components', target_type => 'bom_component', event_prefix => 'bom_component', deferred => true);
select better_supabase.audit('better_supabase.bom_operations', target_type => 'bom_operation', event_prefix => 'bom_operation', deferred => true);
select better_supabase.audit('better_supabase.work_centers', target_type => 'work_center', event_prefix => 'work_center', deferred => true);
select better_supabase.audit('better_supabase.production_order_operations', target_type => 'production_order_operation', event_prefix => 'production_order_operation', deferred => true);
select better_supabase.audit('better_supabase.production_consumptions', target_type => 'production_consumption', event_prefix => 'production_consumption', deferred => true);
select better_supabase.audit('better_supabase.stock_lot_links', target_type => 'stock_lot_link', event_prefix => 'stock_lot_link', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('manufacturing', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
