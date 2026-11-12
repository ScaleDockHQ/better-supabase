-- better-supabase module: vercel-marketplace
-- @bsb-block-data vercel-marketplace
-- @bsb-hash sha256:eca90ca783032ddd52748019cbe99ad19f1851c3a083f1ad16f09d788b76da8b
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('vercel-marketplace', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
