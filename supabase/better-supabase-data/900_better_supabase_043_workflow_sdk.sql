-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:1e002a84dd0a80f2f53cd475a5d2a2eede07d1540b85a1565261c2a8358c723e
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

do $$
declare
  c record;
begin
  for c in select table_name, column_name from information_schema.columns
    where table_schema = 'workflow' and data_type = 'timestamp without time zone'
  loop
    execute format('alter table workflow.%I alter column %I type timestamptz using %I at time zone ''UTC''', c.table_name, c.column_name, c.column_name);
  end loop;
end
$$;

insert into better_supabase.blocks (name, version, mode)
values ('workflow-sdk', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
