-- better-supabase module: sla
-- @bsb-block-data sla
-- @bsb-hash sha256:cb39685a0e9441caa3a35d8177532ca7a9814b961931afd002f80228fc966ae3
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.sla_policies', target_type => 'sla_policy', event_prefix => 'sla_policy', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('sla', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
