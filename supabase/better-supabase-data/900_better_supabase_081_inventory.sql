-- better-supabase module: inventory
-- @bsb-block-data inventory
-- @bsb-hash sha256:1d4193290ceda01d5b5dab87bf27e89240258af98cd13f4882776575fa53e886
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.inventory_locations', target_type => 'inventory_location', event_prefix => 'inventory_location', deferred => true);
select better_supabase.audit('better_supabase.purchase_orders', target_type => 'purchase_order', event_prefix => 'purchase_order', deferred => true);
select better_supabase.audit('better_supabase.purchase_requisitions', target_type => 'purchase_requisition', event_prefix => 'purchase_requisition', deferred => true);
select better_supabase.audit('better_supabase.inventory_receipts', target_type => 'inventory_receipt', event_prefix => 'inventory_receipt', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('inventory', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
