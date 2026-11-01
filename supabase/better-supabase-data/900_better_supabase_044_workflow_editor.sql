-- better-supabase module: workflow-editor
-- @bsb-block-data workflow-editor
-- @bsb-hash sha256:48d23d636108a6736858445513953a952725ba18d63d46926b29ba1251c8e8fe
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

create extension if not exists "pgcrypto" with schema "extensions";

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.workflow_definitions', target_type => 'workflow_definition', event_prefix => 'workflow_definition', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('workflow-editor', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
