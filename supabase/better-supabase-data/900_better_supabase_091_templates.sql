-- better-supabase module: templates
-- @bsb-block-data templates
-- @bsb-hash sha256:23e698b4a62dc6f05efc7081ffc9dee2af054e6f9c1329921f5ab2f2a07adce4
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.templates', target_type => 'template', event_prefix => 'template', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('templates', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
