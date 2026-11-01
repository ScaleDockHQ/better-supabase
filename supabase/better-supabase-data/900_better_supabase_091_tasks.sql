-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:44d10cb245867faf34d16fc66d7eb20c469963326f5b7ec4337194785be8bd62
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.work_items', target_type => 'task', event_prefix => 'task', deferred => true);
select better_supabase.audit('better_supabase.work_projects', target_type => 'project', event_prefix => 'project', deferred => true);
select better_supabase.audit('better_supabase.iterations', target_type => 'iteration', event_prefix => 'iteration', deferred => true);
select better_supabase.audit('better_supabase.work_item_checklist_items', target_type => 'checklist_item', event_prefix => 'checklist_item', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
