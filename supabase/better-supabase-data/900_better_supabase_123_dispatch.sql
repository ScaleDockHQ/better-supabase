-- better-supabase module: dispatch
-- @bsb-block-data dispatch
-- @bsb-hash sha256:566449ba8b3de587164ff69f0f38840f80118679db3881bd096d78c5050171cb
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.work_orders', target_type => 'work_order', event_prefix => 'work_order', deferred => true);
select better_supabase.audit('better_supabase.dispatch_routes', target_type => 'dispatch_route', event_prefix => 'dispatch_route', deferred => true);
select better_supabase.audit('better_supabase.work_order_parts', target_type => 'work_order_part', event_prefix => 'work_order_part', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('dispatch', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
