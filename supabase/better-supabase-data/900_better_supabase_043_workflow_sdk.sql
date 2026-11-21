-- better-supabase module: workflow-sdk
-- @bsb-block-data workflow-sdk
-- @bsb-hash sha256:fe96f31e4db441475b0b8df35cedb14473b1efb14d92a7c69ea65350e54f83ab
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
values ('workflow-sdk', 9, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
