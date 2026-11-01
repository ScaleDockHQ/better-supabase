-- better-supabase module: orders
-- @bsb-block-data orders
-- @bsb-hash sha256:ce6086bafab8841889667391c2a5c3588293525647143c140ef883866a88e31b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.orders', target_type => 'order', event_prefix => 'order', deferred => true);
select better_supabase.audit('better_supabase.carts', target_type => 'cart', event_prefix => 'cart', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('orders', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
