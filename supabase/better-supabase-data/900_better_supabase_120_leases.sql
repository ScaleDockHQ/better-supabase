-- better-supabase module: leases
-- @bsb-block-data leases
-- @bsb-hash sha256:17f0b5a80753a2f0776de9f117d072bdbcc1caecbb89d85c7f20fc15008f9a76
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.leases', target_type => 'lease', event_prefix => 'lease', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('leases', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
