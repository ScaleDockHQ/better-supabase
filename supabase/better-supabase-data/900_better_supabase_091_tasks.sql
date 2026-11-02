-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:d41c6be9606f2599e7035c384844d1120a3bb1321e0b99507a730ed5e6f6cdec
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

-- Realtime for the module's entities (subject.realtime)
select better_supabase.track_realtime('better_supabase.work_items', tenant_column => 'tenant_id');

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
