-- better-supabase module: ai-evals
-- @bsb-block-data ai-evals
-- @bsb-hash sha256:29804813de8ce89a753953e7c33b5e6ba8a2a96b56aa5d12ccea830e60103d08
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-evals', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
