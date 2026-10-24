-- better-supabase module: webhooks-in
-- @bsb-block-data webhooks-in
-- @bsb-hash sha256:91fd97bedb171e9fd711c35ce8cf6c3a3a9330f6edd2527203b23660fc557297
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 4, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
