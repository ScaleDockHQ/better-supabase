-- better-supabase module: assignment
-- @bsb-block-data assignment
-- @bsb-hash sha256:e27546a194847219d3e323c0023bfffc4069ddb575dc1b5742bd6ed7fcdad0e9
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.assignment_queues', target_type => 'assignment_queue', event_prefix => 'assignment_queue', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('assignment', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
