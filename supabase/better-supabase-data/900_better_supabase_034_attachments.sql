-- better-supabase module: attachments
-- @bsb-block-data attachments
-- @bsb-hash sha256:8bdaf0a7ad6cad1fafaa63f09c2777ce7fbd1fee33d6ccc768e4b854c232f591
-- Rows and settings a schema diff doesn't capture. Run `better-supabase add --adopt`
-- after the schema migration to put them in a migration.
-- Managed by `better-supabase add`; re-running it rewrites this file unless it was edited by hand.
-- Change it through `blocks` in better-supabase.config.ts and the module's SQL hooks.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('attachments', 'attachments', false, 52428800, null)
on conflict (id) do update set public = excluded.public;

-- Row audit for the module's tables (blocks.audit.options.blockTables)
select better_supabase.audit('better_supabase.attachments', target_type => 'attachment', event_prefix => 'attachment', deferred => true);

insert into better_supabase.blocks (name, version, mode)
values ('attachments', 8, 'managed')
on conflict (name) do update
  set version = excluded.version, mode = excluded.mode, updated_at = now();
