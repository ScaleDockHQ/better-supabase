-- better-supabase module: webhooks-in
-- @bsb-block-data webhooks-in
-- @bsb-hash sha256:6090e73f7544f584ae30b941a59f7be059403b1db39ed3e3e428861ddc8a5bac
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('webhooks-in', 4, 'adopt')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
