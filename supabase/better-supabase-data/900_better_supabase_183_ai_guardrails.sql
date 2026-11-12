-- better-supabase module: ai-guardrails
-- @bsb-block-data ai-guardrails
-- @bsb-hash sha256:7ad6925143264f72ccb6dee7cd17876e8f63303e2038b6199a6c423a7e9913f2
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into better_supabase.blocks (name, version, mode)
values ('ai-guardrails', 1, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
