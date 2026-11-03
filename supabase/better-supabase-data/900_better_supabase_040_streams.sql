-- better-supabase module: streams
-- @bsb-block-data streams
-- @bsb-hash sha256:3bcf8a9d738998f816711012c470804d7e7c4ee577303fa3c7ed19df65969306
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('streams', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
