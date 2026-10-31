-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:1d33602116152b97634d65a65d0514b39e13976668420f91b0cda1a299acb4b8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
