-- better-supabase module: incoming-webhooks
-- @bsb-block-data incoming-webhooks
-- @bsb-hash sha256:a48c9aadbe0fe57ea99872bf5ebb0df44d21670b48728e6f704aea6cf432c462
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

delete from better_supabase.blocks
  where name = 'webhooks-in'
    and exists (select 1 from better_supabase.blocks where name = 'incoming-webhooks');
update better_supabase.blocks set name = 'incoming-webhooks'
  where name = 'webhooks-in'
    and not exists (select 1 from better_supabase.blocks where name = 'incoming-webhooks');
insert into better_supabase.blocks (name, version, mode)
values ('incoming-webhooks', 5, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
