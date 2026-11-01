-- better-supabase module: approvals
-- @bsb-block-data approvals
-- @bsb-hash sha256:d39f755ab0f5f5d08a01e3cd24ae002907a27d0753b668123f29795c850bedac
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.approval_requests', target_type => 'approval', event_prefix => 'approval', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('approvals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
