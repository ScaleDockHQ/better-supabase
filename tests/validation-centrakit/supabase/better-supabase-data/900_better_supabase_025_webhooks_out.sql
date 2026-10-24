-- better-supabase module: webhooks-out
-- @bsb-block-data webhooks-out
-- @bsb-hash sha256:7603b340f2c43f18cd3ebca2f3276bbd6c81c1be008d984405803ab0df3f6385
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhooks-out', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
