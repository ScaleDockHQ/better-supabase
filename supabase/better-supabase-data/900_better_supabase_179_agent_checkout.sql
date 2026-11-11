-- better-supabase module: agent-checkout
-- @bsb-block-data agent-checkout
-- @bsb-hash sha256:f2ff7f54e754107be5e7c58c415111abecc80d24eacb7640b39ab53ea8c96238
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('agent-checkout', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
