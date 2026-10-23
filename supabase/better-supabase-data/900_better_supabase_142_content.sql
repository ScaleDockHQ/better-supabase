-- better-supabase module: content
-- @bsb-block-data content
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it overwrites this file.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

-- Publishes scheduled content entries when pg_cron is installed.
do $$
begin
  if pg_catalog.to_regnamespace('cron') is not null then
    perform cron.schedule('better-supabase-content-publish', '*/5 * * * *', 'select "better_supabase"."publish_due_content_entries"()');
  else
    raise notice 'pg_cron is not installed: call "better_supabase"."publish_due_content_entries"() on a schedule to publish scheduled content entries';
  end if;
end;
$$;

insert into better_supabase.blocks (name, version, mode)
values ('content', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
