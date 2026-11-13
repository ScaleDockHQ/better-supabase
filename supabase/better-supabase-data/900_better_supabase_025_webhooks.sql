-- better-supabase module: webhooks
-- @bsb-block-data webhooks
-- @bsb-hash sha256:afa9cd603e536b925478edd54d598ecd8364c4a6a8caba256f57effaf9416b21
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

delete from better_supabase.blocks
  where name = 'webhooks-out'
    and exists (select 1 from better_supabase.blocks where name = 'webhooks');
update better_supabase.blocks set name = 'webhooks'
  where name = 'webhooks-out'
    and not exists (select 1 from better_supabase.blocks where name = 'webhooks');
insert into better_supabase.blocks (name, version, mode)
values ('webhooks', 7, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
