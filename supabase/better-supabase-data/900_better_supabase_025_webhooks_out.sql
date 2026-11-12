-- better-supabase module: webhooks-out
-- @bsb-block-data webhooks-out
-- @bsb-hash sha256:5f22915edd50182f39ee43e99696dfd3eea668351b7ec99a7754fc3056536845
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
