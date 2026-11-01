-- better-supabase module: scores
-- @bsb-block-data scores
-- @bsb-hash sha256:810f775915ea54b780507f9dd8604dd208be9bca5ef0f3a6f1d31df45d8a280c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.score_models', target_type => 'score_model', event_prefix => 'score_model', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('scores', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
