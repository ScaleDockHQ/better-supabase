-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:dcd894555c7feed8442fdb2537836d5a60799ce09a4a91b898f5c7583445388c
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
