-- better-supabase module: orders
-- @bsb-block-data orders
-- @bsb-hash sha256:9ed30d81096c3bdb7513abbef921645a893af561edfc75bb6b9a57d3b4bfb7dc
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('orders', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
