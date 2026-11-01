-- better-supabase module: flags
-- @bsb-block-data flags
-- @bsb-hash sha256:1fcf6e4a3cf9cc3d8086e00a92129a0a1ac2a099d12130a3d108f626ece0af00
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.flags', target_type => 'flag', event_prefix => 'flag', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('flags', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
