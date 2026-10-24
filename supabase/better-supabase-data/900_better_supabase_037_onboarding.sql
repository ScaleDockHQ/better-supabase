-- better-supabase module: onboarding
-- @bsb-block-data onboarding
-- @bsb-hash sha256:a7fd47a7b0d152603b5cd802ba44eec18eae8862cdfb4e38e2e7a28f6d5038c2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('onboarding', 2, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
