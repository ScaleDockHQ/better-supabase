-- better-supabase module: shipments
-- @bsb-block-data shipments
-- @bsb-hash sha256:00b866bfbfdf49e28afaca776e11cb39cfb66b84a94438dfed6465486f196d59
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('shipments', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
