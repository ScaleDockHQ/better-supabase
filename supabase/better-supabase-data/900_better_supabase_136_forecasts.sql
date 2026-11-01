-- better-supabase module: forecasts
-- @bsb-block-data forecasts
-- @bsb-hash sha256:56fd601d3dd92737e5b575fd3f55fa5ec74d3726ac3990fa3866b5e2d52e16ef
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.forecast_snapshots', target_type => 'forecast_snapshot', event_prefix => 'forecast_snapshot', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('forecasts', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
