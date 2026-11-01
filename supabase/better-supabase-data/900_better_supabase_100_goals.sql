-- better-supabase module: goals
-- @bsb-block-data goals
-- @bsb-hash sha256:133e146efcb0b66f16e26b67e1184e05bc36eb015d59ef68b62c4318450da573
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.goals', target_type => 'goal', event_prefix => 'goal', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('goals', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
