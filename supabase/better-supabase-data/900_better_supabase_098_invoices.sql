-- better-supabase module: invoices
-- @bsb-block-data invoices
-- @bsb-hash sha256:e18fc61ff94e7b7178a4a1cbb8685d15b7aada2f5858bea4b64848f74c7c7178
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.invoices', target_type => 'invoice', event_prefix => 'invoice', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('invoices', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
