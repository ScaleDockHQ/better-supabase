-- better-supabase module: chat-sdk-state
-- @bsb-block-data chat-sdk-state
-- @bsb-hash sha256:13fb7d7c3b92ac1b9fc68ed93315e9adf0991da9eee6a209717b279ead6e6996
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('chat-sdk-state', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
