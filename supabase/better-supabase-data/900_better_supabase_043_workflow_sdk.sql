-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:5ee85439dd6e5d81bb3d6bcbacb813803d86095a133c7ee23a0555481ceadd9c
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
values ('workflow-sdk', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
