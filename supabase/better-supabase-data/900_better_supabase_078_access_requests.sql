-- better-supabase module: access-requests
-- @bsb-block-data access-requests
-- @bsb-hash sha256:36b60c1acda18eb860ae84fe89060b9312bad9bf644a1a7e514bd2b2f536527a
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.access_requests', target_type => 'access_request', event_prefix => 'access_request', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('access-requests', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
