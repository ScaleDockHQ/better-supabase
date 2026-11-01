-- better-supabase module: passes
-- @bsb-block-data passes
-- @bsb-hash sha256:63104499c4208ff7874aced5ab8d8a28f09c586f98d34c01bcba2fc2e1f5c499
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.passes', target_type => 'pass', event_prefix => 'pass', deferred => true);
select better_supabase.audit('better_supabase.pass_check_ins', target_type => 'pass_check_in', event_prefix => 'pass_check_in', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('passes', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
