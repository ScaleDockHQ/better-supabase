-- better-supabase module: tasks
-- @bsb-block-data tasks
-- @bsb-hash sha256:9f788d88be89da5c5521cce7b829e20d3f9703eeb47b7310bd89847031740643
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Gives each existing project its value of the accounting project dimension.
select "better_supabase"."accounting_sync_dimension_value"(x."tenant_id", 'project', 'Project', x."id"::text, x."key" || ' ' || x."name", x."archived_at" is not null)
from "better_supabase"."work_projects" x
where exists (select 1 from "better_supabase"."accounting_settings" s where s."tenant_id" = x."tenant_id");

insert into better_supabase.blocks (name, version, mode)
values ('tasks', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
