-- better-supabase module: facilities
-- @bsb-block-data facilities
-- @bsb-hash sha256:0fc3b305f352199ddee143353c6ff6eabc40113c999d582a32bdb274960b5a94
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Realtime for the module's entities (subject.realtime)
select better_supabase.track_realtime('better_supabase.maintenance_requests', tenant_column => 'tenant_id');

insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 5, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
