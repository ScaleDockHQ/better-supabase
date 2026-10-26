import type { BlockSqlDefinition } from "../module-types.ts";

import { SCHEMA } from "../shared.ts";

/**
 * Schemas whose tables Supabase or Postgres own; the event trigger leaves them
 * alone.
 */
const ENSURE_RLS_SKIPPED_SCHEMAS = [
  "auth",
  "storage",
  "realtime",
  "_realtime",
  "_analytics",
  "extensions",
  "graphql",
  "graphql_public",
  "vault",
  "pgsodium",
  "pgsodium_masks",
  "net",
  "cron",
  "pgbouncer",
  "supabase_functions",
  "supabase_migrations",
  "information_schema",
];

export const ENSURE_RLS: BlockSqlDefinition = {
  name: "rls-guard",
  title: "RLS on every new table",
  description:
    "An event trigger that enables row level security on every table created outside the Supabase-managed schemas, so a new table is never readable through the Data API before it has policies. Install it as postgres: supautils lets that role create event triggers.",
  requires: [],
  target: "schema",
  build: () => `${SCHEMA}

-- Runs after CREATE TABLE, CREATE TABLE AS and SELECT INTO, and after an
-- ALTER TABLE that turned row level security off. A table without policies
-- then denies every API role until you add one.
create or replace function better_supabase.enable_rls_on_new_table()
returns event_trigger
language plpgsql
set search_path = ''
as $$
declare
  command record;
begin
  for command in
    select objid, schema_name
    from pg_event_trigger_ddl_commands()
    where object_type = 'table'
      and command_tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  loop
    continue when command.schema_name in (${ENSURE_RLS_SKIPPED_SCHEMAS.map((name) => `'${name}'`).join(", ")})
      or command.schema_name like 'pg\\_%';
    continue when exists (
      select 1 from pg_catalog.pg_class
      where oid = command.objid and relrowsecurity
    );
    execute format('alter table %s enable row level security', command.objid::regclass);
  end loop;
end;
$$;

revoke execute on function better_supabase.enable_rls_on_new_table() from public, anon, authenticated;

drop event trigger if exists bsb_ensure_rls;
create event trigger bsb_ensure_rls on ddl_command_end
  when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO', 'ALTER TABLE')
  execute function better_supabase.enable_rls_on_new_table();`,
};
