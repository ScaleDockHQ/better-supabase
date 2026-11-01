-- better-supabase module: agents
-- @bsb-block-data agents
-- @bsb-hash sha256:0c82477b580c6aaebe21d119c34bbf197ecdc306f895b8c70cb85dab84bff208
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.agents', target_type => 'agent', event_prefix => 'agent', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('agents', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
