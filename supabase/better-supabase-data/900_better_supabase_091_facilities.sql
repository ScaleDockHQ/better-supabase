-- better-supabase module: facilities
-- @bsb-block-data facilities
-- @bsb-hash sha256:89a16927d3f0b6762e437d79eba2c06d2d2a03dfb6465befd7e72b1991769298
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.maintenance_requests', target_type => 'task', event_prefix => 'task', deferred => true);
select better_supabase.audit('better_supabase.maintenance_request_checklist_items', target_type => 'checklist_item', event_prefix => 'checklist_item', deferred => true);

alter table better_supabase.blocks add column if not exists block text;
insert into better_supabase.blocks (name, block, version, mode)
values ('facilities', 'tasks', 4, 'managed')
on conflict (name) do update
  set block = excluded.block, version = excluded.version, mode = excluded.mode, updated_at = now();
