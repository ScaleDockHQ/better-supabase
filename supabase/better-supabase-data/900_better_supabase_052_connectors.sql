-- better-supabase module: connectors
-- @bsb-block-data connectors
-- @bsb-hash sha256:f50f2079acb580432a9e5891d777c803ebd103314e3c59eb49d8f42bee0c3a0f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.connector_servers', target_type => 'connector_server', event_prefix => 'connector_server', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('connectors', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
