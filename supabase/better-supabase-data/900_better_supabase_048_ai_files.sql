-- better-supabase module: ai-files
-- @bsb-block-data ai-files
-- @bsb-hash sha256:7aee02a49251d74c98f55d2beb27d7cc09ab284a126a717637efdd0dd61832f8
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('ai-files', 'ai-files', false, 52428800, null)
on conflict (id) do nothing;

insert into better_supabase.blocks (name, version, mode)
values ('ai-files', 3, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
