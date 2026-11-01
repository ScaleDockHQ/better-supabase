-- better-supabase module: facilities
-- @bsb-block-data facilities
-- @bsb-hash sha256:079d083cb64a9488ccab585a68668dbdb4fa8ad7f14e908eabed5d6b72b02338
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Realtime for the module's entities (subject.realtime)
select better_supabase.track_realtime('better_supabase.maintenance_requests', tenant_column => 'tenant_id');

alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 4, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
