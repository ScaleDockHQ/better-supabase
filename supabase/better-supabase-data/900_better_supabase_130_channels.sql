-- better-supabase module: channels
-- @bsb-block-data channels
-- @bsb-hash sha256:082f9e71f0f17e5b8e792b09320851554e48d46b125ad65388203d7028069a4f
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.channels', target_type => 'channel', event_prefix => 'channel', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('channels', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
