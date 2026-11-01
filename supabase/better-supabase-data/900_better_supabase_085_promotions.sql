-- better-supabase module: promotions
-- @bsb-block-data promotions
-- @bsb-hash sha256:f9da48589401e931c35cba5a3ad4fd01a3f55cb0b9cf9b2827b098a886b072dc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.promotions', target_type => 'promotion', event_prefix => 'promotion', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('promotions', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
